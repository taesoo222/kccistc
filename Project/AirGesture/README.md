# AirGesture

Raspberry Pi 카메라로 손동작을 인식해 Windows PC의 동영상 재생과 PowerPoint 슬라이드를 제어하는 시스템입니다.

- 기간 : ~ 2026.10 (대한상공회의소 서울기술교육센터 팀 프로젝트)
- 인원 : 김민, 김태수, 김민준 (5팀 Kim's Room)
- 역할 : <!-- 담당 부분 작성 -->

## 시스템 구조

```
USB 웹캠 (640x480)
   │
Raspberry Pi ── OpenCV 캡처 ── MediaPipe Hands (21개 관절 좌표)
   │
   ├─ 규칙 판별 : 손가락 관절 각도로 펴짐/굽힘 판단
   └─ MLP 보정  : 63 → 64 → 32 → 1, VOLUME_READY 자세 확률
   │
제스처 및 모드 판단 (MAIN / MEDIA / PPT)
   │  HTTP (Bearer 토큰 인증)
Windows PC ── server.py ── YouTube 재생 제어, PowerPoint 슬라이드 제어, 상태 오버레이
```

| 폴더 | 실행 위치 | 내용 |
|---|---|---|
| `AIRGESTURE/` | Raspberry Pi | 손 인식, 제스처 판정, PC로 명령 전송 |
| `AirGesture_PC_bridge/` | Windows PC | 명령 수신, YouTube와 PowerPoint 제어, 오버레이 |
| `experiments/swipe_mlp/` | - | 스와이프 MLP 분류 실험 (최종 버전에서는 사용하지 않음) |

## 핵심 기술

- **관절 각도 판별** : 엄지는 MCP-IP-TIP 각도 145도, 나머지 손가락은 MCP-PIP-TIP 각도 155도를 기준으로 펴짐을 판단
- **MLP 보정** : 각도 규칙이 놓치는 볼륨 자세를 63차원 좌표 입력 MLP로 보정 (확률 0.8 이상).
  손목 기준 이동, 손 크기 정규화, 표준화를 거쳐 손 위치와 카메라 거리 영향을 줄임.
  파라미터 6,209개를 NumPy 행렬곱만으로 계산해 TensorFlow 없이 Pi에서 실시간 동작
- **손목 스와이프** : 손가락 4개의 MCP → DIP 방향 평균으로 손 기울기를 구하고, 기울기 변화량과 속도로 다음/이전 판정

## 결과

| 항목 | 결과 |
|---|---|
| 처리 속도 | 평균 16.3fps (목표 15fps) |
| 오입력 | 명령 제스처 80회 중 중복 실행 1회 |
| 인식 안정성 | 거리 50cm~1.5m, 화면 중심과 모서리에서 성공률 98.7% |
| 볼륨 제스처 인식률 | 규칙만 사용 75% → 규칙과 MLP 보정 88% |

한계 : Air Drawing은 손가락 떨림 보정에 실패해 최종 버전에서 제외했습니다.

## 실행 방법

### 1. Windows PC

Windows용 Python 3, Microsoft Edge, 데스크톱 PowerPoint가 필요합니다.

```bat
cd AirGesture_PC_bridge
python -m pip install -r requirements.txt
python -m playwright install
python server.py
```

터미널에 표시되는 **PC IP**와 **BRIDGE KEY**를 확인합니다. 연결 키(`bridge_key.txt`)는 처음 실행할 때 자동으로 만들어집니다.

### 2. Raspberry Pi

```bash
cd AIRGESTURE
python -m pip install -r requirements.txt
python configure_bridge.py      # PC IP와 BRIDGE KEY 입력 → bridge_config.json 생성
python main.py --camera 0 --headless
```

- 손 랜드마크 모델(`models/hand_landmarker.task`)은 첫 실행 때 자동으로 내려받습니다.
- `--rule-only` : MLP 보정 없이 각도 규칙만으로 실행
- `--no-bridge` : PC 없이 인식만 실행

### 3. 테스트

```bash
cd AIRGESTURE
python -m unittest discover -p "test_*.py"
```
