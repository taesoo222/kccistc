import math
import time
from wrist_swipe import WristSwipeDetector


def _wrap_angle_deg(delta):
    while delta > 180.0:
        delta -= 360.0

    while delta < -180.0:
        delta += 360.0

    return delta


class MotionDetector:

    def __init__(
        self,
        rotation_step_deg=28.0,
        min_rotation_vector=0.08,

        volume_enter_sec=0.25,
        volume_release_sec=0.30,
        volume_cooldown_sec=0.35,
    ):

        # ==============================
        # 회전 설정
        # ==============================
        self.rotation_step_deg = rotation_step_deg
        self.min_rotation_vector = min_rotation_vector

        self.prev_rotation_angle = None
        self.rotation_accum = 0.0

        # ==============================
        # Swipe 설정
        # ==============================
        self.wrist_swipe = WristSwipeDetector()

        # ==============================
        # Volume Barrier 설정
        # ==============================

        # VOLUME_READY가 몇 초 유지되면
        # 실제 Volume Mode에 들어갈지
        self.volume_enter_sec = volume_enter_sec

        # Volume Mode 중 VOLUME_READY가 풀려도
        # 이 시간 동안은 바로 종료하지 않음
        self.volume_release_sec = volume_release_sec

        # Volume Mode 종료 후 바로 다시 들어가는 것 방지
        self.volume_cooldown_sec = volume_cooldown_sec

        # 현재 Volume Mode인지
        self.volume_active = False

        # VOLUME_READY가 처음 시작된 시간
        self.volume_candidate_since = None

        # VOLUME_READY가 풀리기 시작한 시간
        self.volume_release_since = None

        # Volume Mode 종료 후 재진입 금지 시간
        self.volume_cooldown_until = 0.0


    # ============================================================
    # 회전 관련
    # ============================================================

    def reset_rotation(self):
        self.prev_rotation_angle = None
        self.rotation_accum = 0.0


    def _rotation_angle(self, lm):

        thumb = lm[4]
        index = lm[8]

        dx = index.x - thumb.x
        dy = index.y - thumb.y

        distance = math.hypot(
            dx,
            dy
        )

        # 엄지-검지 거리가 너무 가까우면
        # 방향 벡터가 불안정하므로 무시
        if distance < self.min_rotation_vector:
            return None

        # 영상 좌표는 y가 아래쪽으로 증가하기 때문에
        # -dy를 사용하여 일반적인 수학 좌표계로 변경
        angle = math.degrees(
            math.atan2(
                -dy,
                dx
            )
        )

        return angle


    # ============================================================
    # Volume Mode State Machine
    # ============================================================

    def update_volume_state(
        self,
        gesture,
        now
    ):

        # --------------------------------------------------------
        # Volume Mode가 이미 ACTIVE인 경우
        # --------------------------------------------------------
        if self.volume_active:

            # VOLUME_READY가 계속 유지됨
            if gesture == "VOLUME_READY":

                # 해제 타이머 초기화
                self.volume_release_since = None

                return


            # 순간적으로 UNKNOWN / FIST / OPEN_PALM 등이 나온 경우
            # 바로 Volume Mode를 종료하지 않는다.
            if self.volume_release_since is None:

                self.volume_release_since = now

                return


            # VOLUME_READY가 일정 시간 이상 풀려있으면 종료
            release_time = (
                now
                - self.volume_release_since
            )

            if release_time >= self.volume_release_sec:

                self.volume_active = False

                self.volume_release_since = None
                self.volume_candidate_since = None

                self.volume_cooldown_until = (
                    now
                    + self.volume_cooldown_sec
                )

                self.reset_rotation()

                print("[VOLUME] LOCK OFF")

            return


        # --------------------------------------------------------
        # Volume Mode가 아직 ACTIVE가 아닌 경우
        # --------------------------------------------------------

        # Cooldown 중이면 진입 금지
        if now < self.volume_cooldown_until:

            self.volume_candidate_since = None

            return


        # VOLUME_READY가 들어옴
        if gesture == "VOLUME_READY":

            # 처음 감지
            if self.volume_candidate_since is None:

                self.volume_candidate_since = now

                return


            # 얼마나 유지됐는지 계산
            ready_time = (
                now
                - self.volume_candidate_since
            )

            # 0.25초 이상 유지하면
            # Volume Mode 진입
            if ready_time >= self.volume_enter_sec:

                self.volume_active = True

                self.volume_candidate_since = None
                self.volume_release_since = None

                self.reset_rotation()

                print("[VOLUME] LOCK ON")

            return


        # 다른 자세면 후보 초기화
        self.volume_candidate_since = None


    # ============================================================
    # Volume Rotation
    # ============================================================

    def update_rotation(
        self,
        lm
    ):

        # Volume Mode가 아닐 때는 회전 계산하지 않음
        if not self.volume_active:

            self.reset_rotation()

            return None


        angle = self._rotation_angle(lm)


        if angle is None:

            self.reset_rotation()

            return None


        # 첫 프레임
        if self.prev_rotation_angle is None:

            self.prev_rotation_angle = angle

            return None


        delta = _wrap_angle_deg(
            angle
            - self.prev_rotation_angle
        )

        self.prev_rotation_angle = angle


        # 한 프레임에서 갑자기 너무 크게 움직인 경우
        # MediaPipe 좌표 튐으로 간주
        if abs(delta) > 45.0:

            return None


        # 회전 변화량 누적
        self.rotation_accum += delta


        # ----------------------------------------
        # 반시계 방향
        # ----------------------------------------
        if self.rotation_accum >= self.rotation_step_deg:

            self.rotation_accum = 0.0

            return "ROTATE_CCW"


        # ----------------------------------------
        # 시계 방향
        # ----------------------------------------
        if self.rotation_accum <= -self.rotation_step_deg:

            self.rotation_accum = 0.0

            return "ROTATE_CW"


        return None


    # ============================================================
    # Swipe
    # ============================================================

    def reset_swipe(self):
        self.wrist_swipe.reset()

    def update_swipe(self, lm, gesture, now, aspect_ratio=0.75):
        if self.volume_active:
            self.reset_swipe()
            return None
        return self.wrist_swipe.update(lm, gesture, now, aspect_ratio)

    # ============================================================
    # Main Update
    # ============================================================

    def update(
        self,
        lm,
        gesture,
        now=None,
        aspect_ratio=0.75,
    ):

        if now is None:
            now = time.monotonic()
        if lm is None:
            self.volume_active = False
            self.volume_candidate_since = None
            self.volume_release_since = None
            self.reset_rotation()
            self.reset_swipe()
            return None


        # 1.
        # 먼저 Volume Mode 상태를 결정
        self.update_volume_state(
            gesture,
            now
        )


        # ========================================================
        # VOLUME BARRIER ON
        # ========================================================

        if self.volume_active:

            if gesture != "VOLUME_READY":
                self.reset_rotation()
                self.reset_swipe()
                return None

            # Swipe 기록도 제거
            self.reset_swipe()

            # Volume Mode에서는
            # 회전만 처리한다.
            rotation_event = (
                self.update_rotation(lm)
            )

            return rotation_event


        # ========================================================
        # 일반 상태
        # ========================================================

        self.reset_rotation()


        swipe_event = (
            self.update_swipe(
                lm,
                gesture,
                now,
                aspect_ratio,
            )
        )


        return swipe_event
