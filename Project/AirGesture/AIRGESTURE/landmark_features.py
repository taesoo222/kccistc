"""Shared training/inference feature definition; no fitted statistics."""

import numpy as np

FEATURE_VERSION = "wrist_palm_scale_xyz_v1"


def normalize_landmarks(landmarks, width, height):
    """Return 63 float32 values in landmark order (x0,y0,z0,...,x20,y20,z20).

    MediaPipe x and z use image-width units; y uses image-height units.
    Center on wrist, then divide by mean wrist-to-MCP (5,9,13,17) distance.
    Keep rotation/handedness unchanged; use this same function at inference.
    """
    points = np.asarray(landmarks, dtype=np.float32)
    if points.shape != (21, 3) or not np.isfinite(points).all():
        raise ValueError("Expected finite (21, 3) landmarks")
    if width <= 0 or height <= 0:
        raise ValueError("Invalid frame dimensions")
    points = points.copy()
    points[:, 1] *= height / width
    points -= points[0].copy()
    scale = np.linalg.norm(points[[5, 9, 13, 17]], axis=1).mean()
    if not np.isfinite(scale) or scale < 1e-6:
        raise ValueError("Degenerate palm scale")
    return (points / scale).reshape(63)
