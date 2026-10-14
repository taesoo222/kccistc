"""Portable NumPy-only inference for the trained VOLUME_READY MLP."""

from pathlib import Path

import numpy as np

from landmark_features import FEATURE_VERSION, normalize_landmarks

DEFAULT_MODEL = Path(__file__).resolve().parent / "models" / "volume_ready_mlp.npz"


class VolumeReadyMLP:
    def __init__(self, path=DEFAULT_MODEL):
        self.path = Path(path)
        with np.load(self.path, allow_pickle=False) as data:
            if str(data["feature_version"].item()) != FEATURE_VERSION:
                raise ValueError("MLP feature version mismatch; retrain with landmark_features.py")
            self.threshold = float(data["threshold"].item())
            self.mean = data["mean"].astype(np.float32)
            self.scale = data["scale"].astype(np.float32)
            count = int(data["layer_count"].item())
            if not 1 <= count <= 10:
                raise ValueError("Invalid MLP layer count")
            self.weights = [data[f"weight_{i}"].astype(np.float32) for i in range(count)]
            self.biases = [data[f"bias_{i}"].astype(np.float32) for i in range(count)]
        if (self.mean.shape != (63,) or self.scale.shape != (63,)
                or not np.isfinite(self.mean).all() or not np.isfinite(self.scale).all()
                or np.any(self.scale <= 0) or not 0 < self.threshold < 1):
            raise ValueError("Invalid MLP preprocessing metadata")
        previous = 63
        for weight, bias in zip(self.weights, self.biases):
            if (weight.ndim != 2 or weight.shape[0] != previous
                    or bias.shape != (weight.shape[1],)
                    or not np.isfinite(weight).all() or not np.isfinite(bias).all()):
                raise ValueError("Invalid MLP weights")
            previous = weight.shape[1]
        if previous != 1:
            raise ValueError("Expected one binary output")

    def predict_features(self, features):
        """Return positive-class scores for a batch of normalized 63D inputs."""
        values = np.asarray(features, dtype=np.float32)
        if values.ndim != 2 or values.shape[1] != 63 or not np.isfinite(values).all():
            raise ValueError("Expected finite (N, 63) feature matrix")
        values = (values - self.mean) / self.scale
        for index, (weight, bias) in enumerate(zip(self.weights, self.biases)):
            values = values @ weight + bias
            if index < len(self.weights) - 1:
                values = np.maximum(values, 0)
        return (1 / (1 + np.exp(-np.clip(values[:, 0], -60, 60)))).astype(np.float32)

    def predict_landmarks(self, landmarks, width, height):
        points = np.asarray([[lm.x, lm.y, lm.z] for lm in landmarks], dtype=np.float32)
        features = normalize_landmarks(points, width, height)
        return float(self.predict_features(features[None, :])[0])
