"""One clip -> 24 time steps x 66 values; direction uses mirrored preview."""
import numpy as np

LABELS = ('left', 'right', 'none')
STEPS = 24
DURATION = 1.2

def features(points, timestamps, aspect=.75):
    p = np.asarray(points, dtype=np.float64).copy()
    t = np.asarray(timestamps, dtype=np.float64)
    if p.shape != (len(t), 21, 3) or len(t) < 8:
        raise ValueError('Need at least 8 valid landmark frames')
    if not np.isfinite(p).all() or not np.isfinite(t).all() or np.any(np.diff(t) <= 0):
        raise ValueError('Invalid landmarks/timestamps')
    if t[-1]-t[0] < .8 or np.max(np.diff(t)) > .25:
        raise ValueError('Tracking too short or interrupted; record again')
    p[:, :, 1] *= aspect
    scale = np.linalg.norm(p[:, [5,9,13,17]]-p[:, :1], axis=2).mean(axis=1)
    if np.min(scale) < .015:
        raise ValueError('Hand too small')
    wrist = (p[:, 0]-p[0, 0])/np.median(scale)
    shape = ((p-p[:, :1])/scale[:, None, None]).reshape(len(t), 63)
    f = np.concatenate([shape, wrist], axis=1)
    grid = np.linspace(t[0], t[-1], STEPS)
    return np.stack([np.interp(grid,t,f[:,i]) for i in range(66)], axis=1).astype('float32').ravel()

def softmax(x):
    x = x-x.max(axis=-1, keepdims=True)
    e = np.exp(x)
    return e/e.sum(axis=-1, keepdims=True)

class SwipeModel:
    def __init__(self, path):
        with np.load(path, allow_pickle=False) as d:
            self.d = {k:d[k] for k in d.files}
        if int(self.d['steps']) != STEPS or tuple(self.d['labels']) != LABELS:
            raise ValueError('Incompatible swipe model')
    def predict(self, points, timestamps, aspect=.75):
        d=self.d
        x=(features(points,timestamps,aspect)-d['mean'])/d['scale']
        h=np.maximum(0,x@d['w1']+d['b1'])
        return softmax(h@d['w2']+d['b2'])
