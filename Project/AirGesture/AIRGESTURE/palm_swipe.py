"""Horizontal palm displacement, in fractions of the full camera frame width.

The center is the mean x of wrist and four finger bases (0,5,9,13,17).
Three-frame median suppresses isolated tracking jumps. Return to the starting
center rearms the detector without emitting an opposite-direction command.
Input x is already mirrored by the existing camera pipeline.
"""
import math
from collections import deque
import numpy as np

class PalmDisplacementDetector:
    preserve_window=True
    def __init__(self,threshold=.08):self.threshold=threshold;self.reset()
    def reset(self):
        self.values=deque(maxlen=3);self.history=deque();self.baseline=None
        self.last_time=None;self.armed=True;self.cooldown_until=0
        self.center_since=None;self.tilt=0.0;self.detail='POSITION: CALIBRATING'
    @property
    def status(self):return self.detail
    def update(self,lm,gesture,now,aspect_ratio=.75):
        if lm is None or gesture=='OK':
            if self.last_time is not None and now-self.last_time<=.18:return None
            self.reset();return None
        x=float(np.mean([lm[i].x for i in (0,5,9,13,17)]))
        if not math.isfinite(x):return None
        if self.last_time is not None and now-self.last_time>.35:self.reset()
        self.last_time=now;self.values.append(x)
        if len(self.values)<3:return None
        x=float(np.median(self.values))
        if self.baseline is None:self.baseline=x
        dx=x-self.baseline
        self.detail=f'POSITION: {dx*100:+.1f}% / {self.threshold*100:.0f}% | ' + ('READY' if self.armed else 'RETURN TO CENTER')
        if not self.armed:
            if abs(dx)<=self.threshold*.4 and now>=self.cooldown_until:
                if self.center_since is None:self.center_since=now
                if now-self.center_since>=.06:
                    self.armed=True;self.history.clear()
            else:self.center_since=None
            return None
        self.history.append((now,x))
        while self.history and now-self.history[0][0]>.65:self.history.popleft()
        if len(self.history)<3 or abs(dx)<self.threshold or now<self.cooldown_until:return None
        elapsed=now-self.history[0][0];change=x-self.history[0][1]
        if elapsed<=0 or abs(change)<self.threshold*.75 or abs(change)/elapsed<.10 or change*dx<=0:return None
        self.armed=False;self.cooldown_until=now+.18;self.center_since=None
        self.history.clear()
        return 'SWIPE_RIGHT' if dx>0 else 'SWIPE_LEFT'
