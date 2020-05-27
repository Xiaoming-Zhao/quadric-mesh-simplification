import numpy as np
cimport numpy as np
cimport cython
from cpython cimport array
from cpython.exc cimport PyErr_CheckSignals
import array

DTYPE_DOUBLE = np.double
DTYPE_LONG = np.long

ctypedef np.double_t DTYPE_DOUBLE_T
ctypedef np.long_t DTYPE_LONG_T

DEBUG = False

if DEBUG:
    from time import time

from .clean_mesh cimport clean_positions, clean_face, clean_features
from .contract_pair cimport update_pairs, update_face, update_features
from .heap cimport PairHeap
from .maths cimport add_2D
from .mesh_inversion cimport has_mesh_inversion
from .preserve_bounds cimport preserve_bounds
from .q cimport compute_Q
from .targets cimport compute_targets
from .valid_pairs cimport compute_valid_pairs

def simplify_mesh(positions, face_in, num_nodes, features=None, threshold=0.):
    r"""simplify a mesh by contracting edges using the algortihm from `"Surface Simplification Using Quadric Error Metrics"
    <http://mgarland.org/files/papers/quadrics.pdf>`_.

    Args:
        positions (:class:`ndarray`): array of shape num_nodes x 3 containing the x, y, z position for each node
        face (:class:`ndarray`): array of shape num_faces x 3 containing the indices for each triangular face
        num_nodes (number): number of nodes that the final mesh will have
        threshold (number, optional): threshold of vertices distance to be a valid pair

    :rtype: (:class:`ndarray`, :class:`ndarray`)
    """

    # 5. contract vertices until num_nodes reached
    contract(heap, Q, pos, new_positions, feats, face, deleted_pos, deleted_faces, num_nodes)

    # delete positions, faces and features
    pos_copy = clean_positions(pos_copy, deleted_pos_)
    face_copy = clean_face(face_copy, deleted_face_, deleted_pos)

    if DEBUG:
        print('reduction in {} sec'.format(time() - start))

    if features is not None:
        features_copy = clean_features(features_copy, deleted_pos_)
        return pos_copy, face_copy, features_copy
    else:
        return pos_copy, face_copy

@cython.boundscheck(False) # turn off bounds-checking for entire function
@cython.wraparound(False)  # turn off negative index wrapping for entire function
cdef void contract(
    PairHeap heap,
    double [:, :, :] Q,
    double[:, :] pos,
    double[:, :] new_positions,
    double[:, :] features,
    long [:, :] face,
    char [:] deleted_pos,
    char [:] deleted_faces,
    int num_nodes):

    cdef np.ndarray[DTYPE_DOUBLE_T, ndim=1] pos1_, pos2_

    cdef double [:] pos1, pos2, p

    cdef long i, v1, v2, num_deleted_nodes
    cdef char reverse_update

    num_deleted_nodes = 0

    pos1_ = np.zeros((3), dtype=DTYPE_DOUBLE)
    pos2_ = np.zeros((3), dtype=DTYPE_DOUBLE)
    pos1 = pos1_
    pos2 = pos2_

    while heap.length() > 0 and pos.shape[0] - num_deleted_nodes > num_nodes:
        # check if ctrl + c was pressed
        if num_deleted_nodes % 100 == 0:
            PyErr_CheckSignals()
        
        p = heap.pop()
        v1 = <long>p[1]
        v2 = <long>p[2]

        # skip self-loops and already deleted nodes
        if v1 == v2 or deleted_pos[v1] or deleted_pos[v2]:
            continue

        # store values for possible invalid contraction (inverted faces)
        pos1[...] = pos[v1]
        pos2[...] = pos[v2]
        
        new_positions[v1] = p[3:6]

        # update positions if no mesh inversion is created
        reverse_update = has_mesh_inversion(
            v1,
            v2,
            pos,
            new_positions,
            face,
            deleted_faces)

        if reverse_update:
            pos[v1, ...] = pos1
            continue
        else:
            for i in range(3):
                pos[v1, i] = p[3 + i]
            deleted_pos[v2] = True

        # if contraction is valid do updates
        add_2D(Q[v1], Q[v2], Q[v1])
        update_face(v1, v2, face, deleted_faces)
        update_features(p, features)
        update_pairs(v1, v2, heap, pos, Q, features)

        num_deleted_nodes += 1