"""Optional runtime adapter, enabled only after a real swipe model is trained."""
from collections import deque
from functools import lru_cache
from pathlib import Path
import numpy as np
from swipe_features import SwipeModel,DURATION,LABELS
from wrist_swipe import WristSwipeDetector,wrap

@lru_cache(maxsize=4)
def load_model(path):
    model=SwipeModel(path)
    print(f'[SWIPE MLP] Loaded {path} (LEFT / RIGHT / NONE)',flush=True)
    return model

class MLSwipeDetector:
    def __init__(self,path,threshold=.80):
        self.model=load_model(str(Path(path).resolve()));self.threshold=threshold;self.reset()
    def reset(self):
        self.history=deque();self.last_time=None;self.last_prediction=-1e9
        self.armed=True;self.candidate=None;self.candidate_since=None
        self.none_since=None;self.cooldown_until=0;self.detail='ML: COLLECTING MOTION'
        self.tilt=0.0;self.baseline_angle=None
    @property
    def status(self):return self.detail
    def update(self,lm,gesture,now,aspect_ratio=.75):
        if lm is None or gesture=='OK':
            self.history.clear();self.candidate=None;self.candidate_since=None;self.none_since=None
            self.detail='ML: WAIT FOR HAND'
            self.tilt=0.0;self.baseline_angle=None
            return None
        if self.last_time is not None and now-self.last_time>.25:
            self.history.clear();self.candidate=None;self.candidate_since=None;self.none_since=None
            self.tilt=0.0;self.baseline_angle=None
        angle=WristSwipeDetector.hand_angle(lm,aspect_ratio)
        if angle is not None:
            if self.baseline_angle is None:self.baseline_angle=angle
            self.tilt=wrap(angle-self.baseline_angle)
        self.last_time=now
        points=[[p.x,p.y,p.z] for p in lm]
        self.history.append((now,points))
        while self.history and now-self.history[0][0]>DURATION:self.history.popleft()
        if not self.history or now-self.history[0][0]<.8 or now-self.last_prediction<.08:return None
        self.last_prediction=now
        try:
            p=self.model.predict([q for t,q in self.history],[t for t,q in self.history],aspect_ratio)
        except ValueError:
            self.detail='ML: TRACKING INTERRUPTED';return None
        best=int(np.argmax(p));label=LABELS[best]
        self.detail=f'ML: {label.upper()} {p[best]:.0%}'
        if p[2]>=.75:
            if self.none_since is None:self.none_since=now
            if now-self.none_since>=.18 and now>=self.cooldown_until:self.armed=True
        else:self.none_since=None
        if not self.armed:
            self.detail+=' | RETURN TO NEUTRAL';return None
        if best==2 or p[best]<self.threshold or now<self.cooldown_until:
            self.candidate=None;self.candidate_since=None;return None
        if self.candidate!=label:
            self.candidate=label;self.candidate_since=now;return None
        if now-self.candidate_since<.08:return None
        self.armed=False;self.cooldown_until=now+.5
        self.candidate=None;self.candidate_since=None
        return 'SWIPE_LEFT' if label=='left' else 'SWIPE_RIGHT'
