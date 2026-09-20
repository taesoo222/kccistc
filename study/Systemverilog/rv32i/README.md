# RV32I CPU

## RV32I란?

**RV32I**는 RISC-V 명령어 집합 아키텍처(ISA)의 **32비트 기본 정수(Base Integer)** 명령어 세트입니다.
RISC-V는 오픈소스 ISA로, RV32I는 그중에서도 가장 기본이 되는 필수 명령어 집합이며 다음과 같은 특징을 가집니다.

- 레지스터 32개(x0~x31, 32비트), x0은 항상 0으로 고정
- 명령어 길이 고정 32비트, 6가지 인코딩 포맷(R/I/S/B/U/J-type)
- 로드/스토어(Load/Store) 구조: 메모리 접근은 `lw`/`sw` 등 전용 명령어로만 수행
- 산술/논리 연산(R-type), 즉시값 연산(I-type), 분기(B-type), 점프(J-type), 상위 비트 로드(U-type) 등을 지원

이 프로젝트는 RV32I 명령어를 처리하는 CPU를 SystemVerilog로 직접 설계하고, APB 버스를 통해 주변장치(GPIO 등)를 제어하는 것을 목표로 합니다.

## 프로젝트 구성

```
rv32i/
├── src/
│   ├── rv32i_cpu.sv          # rv32i_top, rv32i_cpu 모듈 (control_unit + datapath 연결)
│   ├── control_unit.sv       # FSM 기반 제어 유닛 (FETCH/DECODE/EXECUTE/MEM/WB)
│   ├── datapath.sv           # 레지스터 파일, ALU, PC 등 데이터패스
│   ├── rv32i_pkg.sv          # opcode/명령어 enum 타입 정의 패키지
│   ├── define.svh            # R-type/B-type 명령어 매크로 정의
│   ├── instruction_rom.sv    # 명령어 ROM
│   ├── apb_requester.sv      # CPU ↔ APB 버스 브릿지 (APB Master)
│   ├── apb_bram.sv           # APB 슬레이브 - BRAM (데이터 메모리)
│   ├── apb_gpi.sv            # APB 슬레이브 - General Purpose Input
│   ├── apb_gpo.sv            # APB 슬레이브 - General Purpose Output
│   ├── rom_code_apb_gpi_gpo.mem   # GPI/GPO 테스트용 명령어 코드
│   └── rom_code_sw_sumtest.mem    # 덧셈 테스트용 명령어 코드
└── sim/
    ├── tb_rv32i.sv           # 기본 테스트벤치
    └── tb_rv32i_uvm.sv       # UVM 기반 테스트벤치
```

## 아키텍처

- **CPU 구조**: 멀티사이클(Multi-cycle) 방식. `control_unit`의 FSM이 `FETCH → DECODE → EXECUTE → (MEM) → (WB)` 순서로 상태를 전이하며 명령어를 처리합니다.
- **버스 구조**: CPU는 `apb_requester`를 통해 APB(Advanced Peripheral Bus) 프로토콜로 메모리/주변장치에 접근합니다. `rv32i_top`에서 BRAM, GPI, GPO가 APB 슬레이브로 연결되어 있습니다.
- **지원 명령어 타입** (`rv32i_pkg.sv` 기준):
  - R-type: `ADD SUB SLL SLT SLTU XOR SRL SRA OR AND`
  - I-type(연산): R-type과 동일 ALU 연산 + 즉시값
  - I-type(로드): `lw` 등 메모리 로드
  - S-type: `sw` 등 메모리 스토어
  - B-type: `BEQ BNE BLT BGE BLTU BGEU`
  - U-type: `LUI`, `AUIPC`
  - J-type: `JAL`, `JALR`

## 시뮬레이션

- `sim/tb_rv32i.sv`: 일반 SystemVerilog 테스트벤치
- `sim/tb_rv32i_uvm.sv`: UVM 환경 기반 테스트벤치
- `src/rom_code_sw_sumtest.mem`, `src/rom_code_apb_gpi_gpo.mem`: 시뮬레이션에 사용되는 명령어 ROM 이미지

