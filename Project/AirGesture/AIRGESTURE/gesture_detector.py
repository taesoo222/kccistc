import time


class GestureDetector:

    def __init__(self, fist_release_hold_sec=0.45):

        # FIST가 한번 확정된 뒤
        # 순간적으로 인식이 깨져도 유지할 시간
        self.fist_release_hold_sec = fist_release_hold_sec

        self.last_fist_time = 0.0
        self.fist_active = False


    def detect(self, finger_result, volume_probability=None, volume_threshold=0.8):
        # Keep all original rules. Only rescue FIST/UNKNOWN when the MLP
        # strongly supports VOLUME_READY. Existing volume timing is handled
        # by MotionDetector, so no additional temporal hold is introduced.
        rule_gesture = self._detect_rule(finger_result)
        if finger_result is None or volume_probability is None:
            return rule_gesture

        s = finger_result["states"]
        # Protect mode-selection / exit finger combinations and OPEN_PALM.
        selector = (s["index"] and s["middle"] and not s["pinky"])
        four_fingers = (not s["thumb"] and all(s[name] for name in
                                               ("index", "middle", "ring", "pinky")))
        if (rule_gesture in ("FIST", "UNKNOWN") and not selector and not four_fingers
                and volume_threshold <= volume_probability <= 1.0):
            self.fist_active = False
            return "VOLUME_READY"
        return rule_gesture


    def _detect_rule(self, finger_result):

        if finger_result is None:
            return "NONE"

        s = finger_result["states"]

        thumb = s["thumb"]
        index = s["index"]
        middle = s["middle"]
        ring = s["ring"]
        pinky = s["pinky"]

        now = time.monotonic()


        # ---------------------------------
        # VOLUME READY
        # 엄지 + 검지만 OPEN
        # ---------------------------------
        if (
            thumb
            and index
            and not middle
            and not ring
            and not pinky
        ):

            self.fist_active = False

            return "VOLUME_READY"


        # ---------------------------------
        # OPEN PALM
        # ---------------------------------
        if (
            thumb
            and index
            and middle
            and ring
            and pinky
        ):

            self.fist_active = False

            return "OPEN_PALM"


        # ---------------------------------
        # FIST
        # 엄지는 제외
        # ---------------------------------
        raw_fist = (
            not index
            and not middle
            and not ring
            and not pinky
        )


        if raw_fist:

            self.fist_active = True
            self.last_fist_time = now

            return "FIST"


        # ---------------------------------
        # FIST 유지 Barrier
        # ---------------------------------
        if self.fist_active:

            elapsed = (
                now
                - self.last_fist_time
            )

            if elapsed < self.fist_release_hold_sec:

                return "FIST"

            self.fist_active = False


        return "UNKNOWN"
