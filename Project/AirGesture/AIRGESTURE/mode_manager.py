import time


class ModeManager:
    MAIN = "MAIN"
    MEDIA = "MEDIA"
    PPT = "PPT"
    MOUSE = "MOUSE"
    MOUSE_SELECT = "MOUSE_SELECT"

    PPT_SELECT = "PPT_SELECT"
    MEDIA_SELECT = "MEDIA_SELECT"
    MAIN_SELECT = "MAIN_SELECT"
    NONE = "NONE"

    def __init__(
        self,
        enter_hold_sec=1.0,
        exit_hold_sec=1.2,
        release_sec=0.35,
        exit_grace_sec=0.18,
    ):
        self.mode = self.MAIN

        self.enter_hold_sec = enter_hold_sec
        self.exit_hold_sec = exit_hold_sec
        self.release_sec = release_sec
        self.exit_grace_sec = exit_grace_sec
        self.exit_valid_sec = 0.0
        self.exit_last_valid = None
        self.exit_previous_valid = False

        self.candidate = self.NONE
        self.candidate_since = None

        self.release_gate = False
        self.release_since = None

        self.commands_enabled = False
        self.last_event = None

    def _selector_from_fingers(self, finger_result):
        if finger_result is None:
            return self.NONE

        states = finger_result["states"]

        index = states["index"]
        middle = states["middle"]
        ring = states["ring"]
        pinky = states["pinky"]
        if finger_result.get('main_return', not states["thumb"] and index and middle and ring and pinky):
            return self.MAIN_SELECT

        if index and not middle and not ring and not pinky:
            return self.MOUSE_SELECT

        # 2 fingers = MEDIA
        if (
            index
            and middle
            and not ring
            and not pinky
        ):
            return self.MEDIA_SELECT

        # 3 fingers = PPT
        if (
            index
            and middle
            and ring
            and not pinky
        ):
            return self.PPT_SELECT

        return self.NONE

    def _clear_candidate(self):
        self.candidate = self.NONE
        self.candidate_since = None
        self.exit_valid_sec = 0.0
        self.exit_last_valid = None
        self.exit_previous_valid = False

    def _start_release_gate(self):
        self.release_gate = True
        self.release_since = None
        self.commands_enabled = False
        self._clear_candidate()

    def _change_mode(self, new_mode):
        old_mode = self.mode
        self.mode = new_mode

        self._start_release_gate()

        self.last_event = f"{old_mode}->{new_mode}"

        return self.last_event

    def update(
        self,
        finger_result,
        hand_present=True,
        now=None,
    ):
        if now is None:
            now = time.monotonic()

        selector = (
            self._selector_from_fingers(finger_result)
            if hand_present
            else self.NONE
        )

        self.last_event = None

        if not hand_present:
            self.commands_enabled = False
            self._clear_candidate()
            self.release_since = None
            return None

        # MAIN return takes priority even during selection release / volume lock.
        if self.mode != self.MAIN:
            if selector == self.MAIN_SELECT:
                self.commands_enabled = False
                if self.candidate != self.MAIN_SELECT:
                    self._clear_candidate()
                    self.candidate = self.MAIN_SELECT
                    self.candidate_since = now
                elif self.exit_previous_valid:
                    self.exit_valid_sec += max(0.0, now - self.exit_last_valid)
                elif now - self.exit_last_valid > self.exit_grace_sec:
                    self.exit_valid_sec = 0.0
                    self.candidate_since = now
                self.exit_last_valid = now
                self.exit_previous_valid = True
                if self.exit_valid_sec >= self.exit_hold_sec:
                    return self._change_mode(self.MAIN)
                return None
            if self.candidate == self.MAIN_SELECT:
                self.exit_previous_valid = False
                if now - self.exit_last_valid <= self.exit_grace_sec:
                    self.commands_enabled = False
                    return None
                self._clear_candidate()

        # ==========================================
        # 모드 변경 직후 Release Barrier
        # ==========================================
        # In MAIN, a new two/three-finger pose is already a release of the
        # four-finger return pose. Start its normal hold without requiring a fist.
        if self.release_gate and self.mode == self.MAIN and selector != self.MAIN_SELECT:
            self.release_gate = False
            self.release_since = None
            self._clear_candidate()
        if self.release_gate:
            self.commands_enabled = False

            if selector == self.NONE:
                if self.release_since is None:
                    self.release_since = now

                elif (
                    now - self.release_since
                    >= self.release_sec
                ):
                    self.release_gate = False
                    self.release_since = None

                    self.commands_enabled = (
                        self.mode != self.MAIN
                    )

            else:
                self.release_since = None

            return None

        # ==========================================
        # MAIN MODE
        # ==========================================
        if self.mode == self.MAIN:
            self.commands_enabled = False

            if selector not in (
                self.MOUSE_SELECT,
                self.MEDIA_SELECT,
                self.PPT_SELECT,
            ):
                self._clear_candidate()
                return None

            # 새 선택 후보 시작
            if self.candidate != selector:
                self.candidate = selector
                self.candidate_since = now
                return None

            held = (
                now
                - self.candidate_since
            )

            # 1초 유지 후 모드 진입
            if held >= self.enter_hold_sec:

                if selector == self.MOUSE_SELECT:
                    return self._change_mode(self.MOUSE)

                # 2 fingers -> MEDIA
                if selector == self.MEDIA_SELECT:
                    return self._change_mode(
                        self.MEDIA
                    )

                # 3 fingers -> PPT
                if selector == self.PPT_SELECT:
                    return self._change_mode(
                        self.PPT
                    )

            return None

        # ==========================================
        # MEDIA / PPT MODE
        # ==========================================
        self.commands_enabled = True

        self._clear_candidate()

        return None

    def get_candidate_progress(
        self,
        now=None,
    ):
        if now is None:
            now = time.monotonic()

        if self.candidate_since is None:
            return 0.0
        if self.candidate == self.MAIN_SELECT:
            return min(1.0, self.exit_valid_sec / max(self.exit_hold_sec, 1e-6))

        if self.mode == self.MAIN:
            target = self.enter_hold_sec
        else:
            target = self.exit_hold_sec

        if target <= 0:
            return 1.0

        progress = (
            now
            - self.candidate_since
        ) / target

        return min(
            1.0,
            max(
                0.0,
                progress,
            ),
        )

    def get_candidate_label(self):
        if self.candidate == self.MOUSE_SELECT:
            return "MOUSE"

        if self.candidate == self.MEDIA_SELECT:
            if self.mode == self.MAIN:
                return "MEDIA"

        if self.candidate == self.PPT_SELECT:
            if self.mode == self.MAIN:
                return "PPT"

        if self.candidate == self.MAIN_SELECT:
            return "EXIT TO MAIN (4 FINGERS)"

        return "NONE"
