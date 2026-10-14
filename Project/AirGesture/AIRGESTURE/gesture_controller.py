"""Shared frame-to-command pipeline for the webcam and deterministic tests."""
import time

from control_settings import (MODE_ENTER_SECONDS, MAIN_RETURN_SECONDS,
                              MODE_RELEASE_SECONDS, MAX_FRAME_GAP_SECONDS)
from gesture_detector import GestureDetector
from mode_manager import ModeManager
from motion_detector import MotionDetector
from media_commands import MediaCommandDetector
from main_return_pose import main_return_pose
from wrist_swipe import WristSwipeDetector
from swipe_session import SwipeSession
from ok_pose import is_ok_pose,ok_pose_details


def media_swipe_exit_pose(fingers):
    if fingers is None:return False
    states=fingers['states']
    return (states['thumb'] and states['index'] and states['pinky']
            and not states['middle'] and not states['ring'])


class GestureController:
    def __init__(self):
        # Symmetric media debounce replaces the old FIST-only hold in this app.
        self.gestures = GestureDetector(fist_release_hold_sec=0.0)
        self.modes = ModeManager(MODE_ENTER_SECONDS, MAIN_RETURN_SECONDS, MODE_RELEASE_SECONDS)
        self.motion = MotionDetector()
        self.media = MediaCommandDetector()
        self.media_exit_blocked = False
        self.media_exit_until = 0.0
        self.media_exit_release_since = None
        self.last_time = None
        self.deferred_swipe = None
        self.media_swipe = WristSwipeDetector()
        self.swipe = SwipeSession()

    def update(self, fingers, landmarks, volume_probability=None, threshold=0.8,
               now=None, aspect_ratio=0.75):
        now = time.monotonic() if now is None else now
        if self.last_time is not None and now - self.last_time > MAX_FRAME_GAP_SECONDS:
            self.deferred_swipe = None
            self.modes.update(None, hand_present=False, now=now)
            self.motion = MotionDetector()
            self.media.cancel_pending()
            self.gestures = GestureDetector(fist_release_hold_sec=0.0)
            self.media_swipe = WristSwipeDetector()
            self.swipe.interrupt_tracking()
        self.last_time = now
        present = fingers is not None and landmarks is not None
        volume_busy = (self.modes.mode == ModeManager.MEDIA and not self.swipe.active and
                       (self.motion.volume_active or self.motion.volume_candidate_since is not None
                        or now < self.motion.volume_cooldown_until))
        ok = (not volume_busy and self.modes.mode in (ModeManager.MEDIA,ModeManager.PPT) and
              is_ok_pose(fingers,landmarks,aspect_ratio))
        self.return_pose = main_return_pose(fingers, landmarks, aspect_ratio) if present else None
        if present:
            # The relaxed four-finger return check is only for leaving a mode.
            # In MAIN it can otherwise swallow PPT's folded-pinky selector.
            fingers = {**fingers, 'main_return': (self.modes.mode != ModeManager.MAIN
                       and self.return_pose['matched'] and not ok)}
        event = self.modes.update(fingers, hand_present=present, now=now)
        gesture = self.gestures.detect(fingers if present else None, volume_probability, threshold)
        if ok: gesture = 'OK'
        exit_pose = present and media_swipe_exit_pose(fingers)
        if self.modes.mode == ModeManager.MEDIA and exit_pose and (self.swipe.active or self.media_exit_blocked):
            gesture = 'SWIPE_EXIT'
        if event:
            self.media_exit_blocked = False
            self.media_exit_release_since = None
            self.deferred_swipe = None
            self.motion = MotionDetector()
            self.media = MediaCommandDetector()
            self.media_swipe = WristSwipeDetector()
            self.swipe = SwipeSession()

        self.swipe.ok_debug=ok_pose_details(fingers,landmarks,aspect_ratio)
        self.swipe.exit_gesture = 'SWIPE_EXIT' if self.modes.mode == ModeManager.MEDIA else 'FIST'
        command = motion_event = None
        if not self.modes.commands_enabled:
            self.swipe.fist_since = None
            # A brief four-finger MAIN candidate must not erase the temporal
            # detector's entire window. Keep observing, but emit no commands.
            if self.swipe.active and (hasattr(self.swipe.detector, 'model') or
                                      getattr(self.swipe.detector, 'preserve_window', False)):
                if not present:
                    self.deferred_swipe=None
                    self.swipe.interrupt_tracking(preserve_model=True)
                observed = self.swipe.detector.update(landmarks, gesture, now, aspect_ratio)
                if observed and gesture not in ('FIST', 'SWIPE_EXIT', 'VOLUME_READY'):self.deferred_swipe = (now, observed)
            else:
                self.deferred_swipe = None
                self.swipe.interrupt_tracking()
            self.motion.update(None, 'NONE', now=now)
            self.media.update('NONE', now, blocked=True)
        elif self.modes.mode == ModeManager.MEDIA and self.media_exit_blocked:
            # Require cooldown plus a visible release; holding the exit pose
            # cannot retrigger next/play/volume or immediately re-enter swipe.
            self.deferred_swipe = None
            self.media.update('NONE', now, blocked=True)
            self.motion = MotionDetector()
            if present and not exit_pose:
                if self.media_exit_release_since is None:self.media_exit_release_since=now
                if now >= self.media_exit_until and now-self.media_exit_release_since >= .25:
                    self.media_exit_blocked=False
            else:
                self.media_exit_release_since=None
        elif self.modes.mode in (ModeManager.MEDIA, ModeManager.PPT):
            volume_blocked = (self.motion.volume_active or
                              self.motion.volume_candidate_since is not None or
                              now < self.motion.volume_cooldown_until)
            if volume_blocked and not self.swipe.active:
                # Do not let an OK misclassification cancel a volume lock.
                # Require release before a fresh OK hold can enter swipe.
                self.swipe.interrupt_tracking()
                self.swipe.ready = False
                self.deferred_swipe = None
                exited = False
            else:
                # OK can enter only after volume release and its cooldown.
                if ok:
                    self.motion = MotionDetector()
                    self.media.cancel_pending()
                exited = self.swipe.update(landmarks, gesture, now)
            if exited:
                self.deferred_swipe = None
                self.media = MediaCommandDetector()
                self.motion = MotionDetector()
                if self.modes.mode == ModeManager.MEDIA:
                    # Exiting is a state transition only: never advance or play a video.
                    self.media_exit_blocked = True
                    self.media_exit_until = now + .8
                    self.media_exit_release_since = None
            elif self.swipe.active:
                # Exclusivity: no PLAY, PAUSE or volume operations in this state.
                self.media.update('NONE', now, blocked=True)
                self.motion.update(None, 'NONE', now=now)
                motion_event = (None if gesture in ('FIST', 'SWIPE_EXIT', 'VOLUME_READY') else self.swipe.detector.update(
                    landmarks, gesture, now, aspect_ratio))
                if gesture in ('FIST', 'SWIPE_EXIT', 'VOLUME_READY'):
                    motion_event = None
                    self.deferred_swipe = None
                    self.swipe.detector.reset()
                if self.deferred_swipe is not None:
                    observed_at, observed = self.deferred_swipe
                    self.deferred_swipe = None
                    if motion_event is None and now-observed_at<=.25:
                        motion_event = observed
                if self.modes.mode == ModeManager.PPT:
                    command = {'SWIPE_RIGHT':'PREVIOUS','SWIPE_LEFT':'NEXT'}.get(motion_event)
                else:
                    command = {'SWIPE_RIGHT':'VIDEO_PREVIOUS','SWIPE_LEFT':'VIDEO_NEXT'}.get(motion_event)
            else:
                if self.modes.mode == ModeManager.MEDIA:
                    motion_event = self.motion.update(
                        landmarks, 'VOLUME_READY' if gesture == 'VOLUME_READY' else 'UNKNOWN',
                        now=now, aspect_ratio=aspect_ratio)
                    blocked = (gesture == 'VOLUME_READY' or self.motion.volume_active or
                               self.motion.volume_candidate_since is not None or
                               now < self.motion.volume_cooldown_until)
                    command = self.media.update(
                        gesture, now, blocked=blocked)
                    if motion_event in ('ROTATE_CW','ROTATE_CCW'):
                        command = 'VOLUME_UP' if motion_event == 'ROTATE_CW' else 'VOLUME_DOWN'
                else:
                    self.media.update('NONE', now, blocked=True)
        else:
            self.swipe = SwipeSession()
        return {"gesture": gesture, "mode_event": event, "motion": motion_event,
                "command": command, "mode": self.modes.mode,
                "enabled": self.modes.commands_enabled,
                "volume_lock": self.motion.volume_active,
                "swipe_active": self.swipe.active, "swipe_status": (
                    'SWIPE EXIT: COOLDOWN / RELEASE EXIT POSE' if self.media_exit_blocked else self.swipe.status),
                "swipe_tilt": float(getattr(self.swipe.detector, 'tilt', 0.0))}
