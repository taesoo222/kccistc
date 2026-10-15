# Synchronous FIFO UVM 검증

16 x 8bit 동기식 FIFO를 SystemVerilog로 설계하고, UVM 1.2로 검증 환경을 구성한 미니 프로젝트입니다.
시뮬레이션은 Synopsys VCS, 파형과 커버리지 확인은 Verdi를 사용했습니다.

## 폴더 구성

```
fifo_UVM/
├── src/
│   └── fifo_sv.sv        # fifo_sv (top), fifo_control_unit, registerfile_sv
├── sim/
│   └── tb_fifo_uvm.sv    # interface, UVM 컴포넌트, test, tb top
└── Makefile
```

## DUT

`fifo_sv`는 포인터와 full/empty를 관리하는 `fifo_control_unit`과 8bit x 16 메모리인 `registerfile_sv`로 나뉩니다.

- 깊이는 `WIDTH` 파라미터로 정합니다 (`WIDTH = 4` 이면 16칸).
- 리셋은 동기식 active-low 입니다.
- 읽기는 `rdata = mem[rptr]` 조합 출력이라 pop 전에도 맨 앞 데이터가 보입니다 (FWFT).
- full/empty는 포인터 비트를 늘리는 대신 레지스터로 따로 두고, 다음 포인터 값을 비교해서 갱신합니다.
- push와 pop이 동시에 들어오면 full일 때는 pop만, empty일 때는 push만 하고, 그 외에는 둘 다 수행합니다.

## 테스트벤치 구조

```
fifo_test
└── fifo_environment
    ├── fifo_agent
    │   ├── sequencer
    │   ├── fifo_driver    -> fifo_if (drv_cb, negedge)
    │   └── fifo_monitor   <- fifo_if (mon_cb, posedge)
    ├── fifo_scoreboard    <- monitor
    └── fifo_coverage      <- monitor
```

- scoreboard는 `bit [7:0] q[$]` 큐로 FIFO 동작을 따라가는 reference model을 두고, 매 사이클 full, empty, rdata를 비교합니다.
- coverage는 push/pop 조합, full/empty 상태, 그리고 둘의 cross를 보고, wdata/rdata는 0~255 값을 다 써봤는지 확인합니다.
- interface에 full과 empty가 동시에 1이 되면 안 된다는 assertion을 넣었습니다.

### 드라이버/모니터 타이밍

드라이버는 negedge 1ns 뒤에 값을 넣고, 모니터는 posedge 직전 값(`#1step`)을 읽도록 반 주기를 띄웠습니다.
이렇게 하면 모니터가 읽는 값은 "이번 엣지에 들어갈 입력"과 "엣지 전 DUT 상태"가 한 묶음이 되고,
scoreboard는 비교를 먼저 한 뒤 큐를 갱신하면 DUT와 같은 순서로 동작하게 됩니다.

## 테스트 시나리오

`fifo_test`에서 아래 순서로 시퀀스를 실행합니다.

1. reset 5사이클
2. push만 32번 (깊이의 2배) 해서 full과 overflow 차단 확인, 이어서 push+pop 동시 5번
3. pop만 32번 해서 empty와 underflow 차단 확인, 이어서 push+pop 동시 5번
4. 다시 가득 채운 상태에서 reset
5. 랜덤 5000번 (push:pop:동시:idle = 4:4:1:1, 2% 확률로 중간 reset)

2~4번은 랜덤으로는 잘 안 나오는 경계 상황을 일부러 만들기 위한 것이고, 5번에서 일반적인 동작과 중간 리셋을 넓게 봅니다.

## 트러블슈팅: 첫 사이클 X 문제

처음 돌렸을 때 시뮬레이션 시작 직후 assertion 에러가 하나 뜨고, scoreboard의 skip 횟수가 드라이버가 넣은 리셋 횟수와 맞지 않았습니다.

원인은 첫 posedge(5ns) 시점이었습니다. 드라이버는 clocking block으로 negedge + 1ns에 값을 넣기 때문에
첫 posedge에서는 아직 아무 값도 들어가지 않아 rst_n, push, pop이 모두 X였습니다.
assertion은 `disable iff (!rst_n)`였는데, rst_n이 X면 `!rst_n`도 X라서 disable이 되지 않고
X인 full/empty로 검사를 해버렸습니다.

그래서 다음과 같이 고쳤습니다.

- assertion: `disable iff (!rst_n || $isunknown(rst_n))`로 X 구간을 제외
- scoreboard: `rst_n !== 1'b1`(4-state 비교)로 X인 사이클도 리셋처럼 건너뛰도록 처리

이 때문에 scoreboard의 skip 횟수는 드라이버 리셋 횟수보다 1 많게 나오는데, 첫 사이클 X를 건너뛴 것이라 정상입니다.

## 실행 방법

VCS와 Verdi가 설치된 Linux 서버에서 실행합니다.

```bash
make            # 컴파일 + 시뮬레이션
make compile    # 컴파일만
make sim        # 시뮬레이션만 (sim.log)
make verdi      # 파형 (wave.fsdb)
make cov        # 커버리지 GUI
make urg        # 커버리지 텍스트 리포트 (urgReport/)
make clean
```

`make sim VERBOSITY=UVM_LOW`로 로그를 줄일 수 있고, `make compile FSDB=0`이면 파형을 덤프하지 않습니다.

## 아쉬운 점

- 드라이버가 아이템 사이에 신호를 idle로 내리지 않아서, 시퀀스 사이에는 마지막 push/pop 값이 그대로 유지됩니다.
  모니터가 실제 핀 값을 보기 때문에 검증 결과에는 영향이 없지만, 파형을 볼 때 헷갈릴 수 있습니다.
- coverage가 리셋 중인 사이클도 샘플해서, 일부 cross bin은 리셋 시퀀스 덕분에 채워집니다. 리셋 구간은 빼고 보는 게 더 정확합니다.
- 데이터 폭이 8bit로 고정되어 있어 `DATA_WIDTH` 파라미터로 빼면 재사용하기 더 좋을 것 같습니다.
