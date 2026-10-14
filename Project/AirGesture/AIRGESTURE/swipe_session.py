"""OK enters swipe mode; a held fist exits. Tracking loss never changes the latch."""
from palm_swipe import PalmDisplacementDetector

_announced = False

def create_detector():
    # An existing swipe_mlp.npz must not silently select the previous backend.
    global _announced
    if not _announced:
        print('[SWIPE] Palm displacement: 8% frame width (~51px at 640); OK enters / MEDIA: thumb+index+pinky exits / PPT: FIST exits')
        _announced = True
    return PalmDisplacementDetector(threshold=.08)

from control_settings import MAX_FRAME_GAP_SECONDS
SWIPE_HOLD_SECONDS=.35
OK_RELEASE_SECONDS=.25
FIST_EXIT_SECONDS=.35

class SwipeSession:
    def __init__(self):
        self.detector=create_detector()
        self.active=False
        self.ok_since=self.release_since=self.last_time=None
        self.ready=True
        self.fist_since=None
        self.exit_gesture='FIST'
        self.ok_debug=None
        self.ok_valid=0.0
        self.previous_ok=False
        self.last_ok=None
    @property
    def status(self):
        if self.active:
            exit_hint='THUMB+INDEX+PINKY 0.4s: EXIT ONLY' if self.exit_gesture=='SWIPE_EXIT' else 'FIST 0.35s TO EXIT'
            return 'SWIPE: ' + self.detector.status + ' | ' + exit_hint
        if self.ok_debug is not None:
            ratio=self.ok_debug.get('pinch_ratio')
            if ratio is not None:
                progress=min(100,round(self.ok_valid/SWIPE_HOLD_SECONDS*100))
                return f'OK: PINCH {ratio:.2f}/0.35 FINGERS {self.ok_debug["extended"]}/2 HOLD {progress}%'
        return 'OK SIGN 0.35s FOR SWIPE'
    def interrupt_tracking(self,preserve_model=False):
        if not preserve_model:self.detector.reset()
        self.ok_since=self.release_since=None
        self.fist_since=None
        self.ok_valid=0.0
        self.previous_ok=False
        self.last_ok=None
        # Preserve active and ready: disappearance is not a deliberate OK release.
    def update(self,lm,gesture,now):
        if self.last_time is not None and now-self.last_time>MAX_FRAME_GAP_SECONDS:
            self.interrupt_tracking()
        dt=0.0 if self.last_time is None else max(0.0,now-self.last_time)
        self.last_time=now
        if lm is None:
            self.interrupt_tracking()
            return False
        if self.active:
            # The controller selects a mode-specific exit pose.
            if gesture==self.exit_gesture:
                if self.fist_since is None:self.fist_since=now
                hold=.4 if self.exit_gesture=='SWIPE_EXIT' else FIST_EXIT_SECONDS
                if now-self.fist_since>=hold-1e-9:
                    self.active=False
                    self.ready=True
                    self.interrupt_tracking()
                    return True
            else:
                self.fist_since=None
            return False
        if gesture=='OK':
            self.release_since=None
            if not self.ready:return False
            if self.ok_since is None:self.ok_since=now
            if self.previous_ok:self.ok_valid+=dt
            self.previous_ok=True
            self.last_ok=now
            if self.ok_valid>=SWIPE_HOLD_SECONDS-1e-9:
                self.active=True
                self.ready=False
                self.ok_since=None
                self.ok_valid=0.0
                self.previous_ok=False
                self.detector.reset()
                return False
        else:
            self.previous_ok=False
            # A brief pose dropout contributes no hold time, but does not
            # discard accumulated valid OK frames or count as a new OK sign.
            if self.last_ok is not None and now-self.last_ok<=0.15:
                if self.release_since is None:self.release_since=now
                return False
            self.ok_since=None
            self.ok_valid=0.0
            if self.release_since is None:self.release_since=now
            if now-self.release_since>=OK_RELEASE_SECONDS-1e-9:
                self.ready=True
        return False
