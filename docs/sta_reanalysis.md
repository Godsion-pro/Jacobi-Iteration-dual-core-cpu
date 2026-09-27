# STA 재분석 (2026, 프로젝트 종료 후 추가 연구)

과제 보고서에는 "div 명령 지연 2.624 ns, 추정 최대 클럭 약 375 MHz"라고 적었습니다. 이 값은 게이트 레벨 시뮬레이션에서 div 명령 1건을 관측한 것이라, 정적 타이밍 분석(STA) 기준의 Fmax라고 할 수 없습니다. 그래서 원본 RTL을 공개 툴체인으로 다시 합성하고 STA를 했습니다.

셀 라이브러리가 보고서와 달라 **절대값은 비교 대상이 아닙니다.** 이 분석으로 확인하려는 것은 세 가지입니다.

1. 크리티컬 패스가 어디인지
2. false path가 STA 결과를 어떻게 부풀리는지
3. 구조 개선이 실제로 효과가 있는지

## 요약 (Nangate45 typical)

| 항목 | 결과 |
|---|---|
| Fmax를 결정하는 경로 | div → RF, **54.03 ns → Fmax 18.5 MHz** (같은 비트끼리 가는 직접 경로 기준). 조합 64비트 나눗셈기 |
| div를 제외했을 때 다음 병목 | mul → RF, 7.29 ns (137 MHz) |
| 제약 없이 본 최악 경로 | div → ALU 결과 → zero → 분기 mux → PC, 55.38 ns. div 실행 중에는 branch=0이라 **실제로 쓰이지 않는 경로(false path)** |
| 개선안: zero를 전용 비교기로 분리 | beq 경로 **6.92 → 5.13 ns (−26%)**. self-check TB에서 기능 동일 확인 |
| 개선안: 나눗셈 → 역수 곱셈 (recip) | 제약 없는 최악 경로 **55.38 → 6.70 ns (8.3×)**, 면적 50,386 → 34,322 µm² (−32%). 사이클 수 동일, 결과는 x4만 1 LSB 차이 |
| 보고서 2.624 ns | 45 nm typ에서도 나눗셈기 최악 지연이 약 54 ns. 특정 피연산자에서 관측한 값으로 판단 |
| 버퍼링까지 한 재측정 (OpenROAD) | 합성 넷리스트에 max slew/cap 위반이 수백 개 있어 합성 직후 수치가 부풀려져 있었음. 배치 → repair_design → CTS → repair_timing 후 recip + zero 비교기 6.68 → **2.77 ns** |
| 개선안: 5단 파이프라인 | 합성 직후에는 주기 1.9배 단축(3.53 ns)으로 보였으나, 수리 후 2.77 → 2.39 ns(1.16×). 사이클 44 → 51까지 넣으면 **반복 1회 시간은 비슷**(121.7 vs 121.9 ns). 병목은 곱셈기 |

## 환경

| 단계 | 도구 | 비고 |
|---|---|---|
| SV → Verilog | sv2v v0.0.12 | Yosys 0.33이 interface 안의 unpacked 배열을 처리하지 못해 사용 |
| 합성 | Yosys 0.33 + ABC | 셀 라이브러리 Nangate45 (FreePDK45) typical |
| STA | OpenSTA 3.1.0 (`ef17b3f`) | slow / typ / fast 3개 corner |
| 조건 | 클럭 10 ns, ideal clock (CTS 이전), 배선 기생 성분 없음 | `T_min = 10 ns − worst slack` (clk→Q와 setup 포함) |

합성 결과는 34,849 cells, 50,386 µm², FF 2,436개입니다(RF 1,088 / DMEM 1,152 / 교환 버퍼 128 / PC 68). 합성 후 latch는 0개로, Verilator의 ALU LATCH 경고는 실제 합성에서는 사라지는 경고였습니다.

## 흐름

```
rtl/*.sv ─(`include 제거)─> sv2v ─> design.v ─> Yosys synth ─> netlist.v ─> OpenSTA × 3 corner × 7 mode
             syn/flow.sh               syn/syn.ys                        syn/sta_mode.tcl, syn/run_sta.sh
```

1. **합성용 top (`syn/syn_top.sv`)**: 원본 `top`은 출력 포트가 없어서, 합성기가 관측되지 않는 로직을 전부 지웁니다. 그래서 코어 간 교환 버퍼 4 word를 출력으로 꺼내는 래퍼를 둡니다. 모든 datapath가 교환 버퍼에 영향을 주기 때문에, 이것만으로 로직이 남습니다.
2. **`include` 정리**: 원본은 공용 모듈을 두 번 `include`합니다. 파일별로 `include` 줄을 빼고 한꺼번에 넘깁니다.
3. **sv2v**: interface 포트를 가진 모듈을 top으로 인라인하고, 버퍼를 `syn_top.intf.*`로 참조합니다. Yosys가 읽을 수 있게 `intf.*`로 바꿉니다.
4. **Yosys**: 모듈 경계 신호(`instruction`, `read_data_*`, `ALU_operand2`, `AluData`, `MemData`, `Mem_or_ALU`, `zero`, `ALUoperation`, `branch`)에 `keep`을 걸어, 경로 리포트에서 어느 단계를 지나는지 보이게 합니다.
5. **OpenSTA**: 클럭과 입출력 지연만 준 기본 분석(`none`)과, 명령어 종류별 분석(아래)을 3개 corner에서 돌립니다.

## 명령어 종류별 분석 방법

단일 사이클 CPU는 모든 명령이 같은 조합 논리를 공유합니다. STA는 데이터와 무관하게 구조적으로 가장 긴 경로를 보기 때문에, **어떤 명령에서도 신호가 타지 않는 경로**가 최악으로 잡힐 수 있습니다. 그래서 명령어 종류마다 아래 제약을 걸고 따로 분석했습니다.

| mode | case analysis | false path | 이유 |
|---|---|---|---|
| none | 없음 | 없음 | 일반 STA가 보고하는 값 |
| div / mul / add | `ALUoperation` = 101 / 011 / 010, `branch` = 0 | MemData를 지나는 경로, DMEM·교환 버퍼로 가는 경로, ALU 결과 → PC | memRead=0, memWrite=0, rec=0, branch=0 |
| lw | `ALUoperation` = 010, `branch` = 0 | DMEM·교환 버퍼로 가는 경로, ALU 결과 → PC | memWrite=0 |
| sw | `ALUoperation` = 010, `branch` = 0 | RF로 가는 경로, ALU 결과 → PC | RegWrite=0 |
| beq | `ALUoperation` = 110, `branch` = 1 | RF·DMEM·교환 버퍼로 가는 경로 | RegWrite=0, memWrite=0 |

진행하면서 막혔던 점도 적어 둡니다.

- **opcode 비트 고정은 소용없었습니다.** 처음에는 명령어 opcode 비트를 상수로 고정했지만 ALU 연산 선택이 고정되지 않았습니다. ABC가 명령어 ROM과 제어 디코더를 합쳐, 제어 신호를 PC에서 바로 계산하도록 논리를 재구성했기 때문입니다. 그래서 구동 셀이 남아 있는 `ALUoperation`과 `branch`에 직접 case analysis를 걸었습니다.
- **일부 제어 신호는 사라졌습니다.** `memRead`, `memWrite`, `RegWrite`는 합성 후 구동 셀이 없어져 case analysis를 걸 수 없었습니다. 그래서 해당 FF 그룹으로 가는 경로를 false path로 지정해 대신했습니다.
- **PC FF는 뺄셈으로 정의했습니다.** PC 일부 비트의 Q 신호 이름이 합성 중 익명(`_00008_` 등)이 되어, 이름으로는 모을 수 없었습니다. 그래서 "전체 FF − RF − DMEM − 교환 버퍼"를 PC로 정의했습니다.

### 직접 경로 측정 (`T_direct`)

div 모드의 최악 경로를 보면 `AluData[2] → Mem_or_ALU[0]`처럼 비트 번호가 바뀝니다. ALU 결과가 DMEM 읽기 주소로 쓰였다는 뜻이고, div에서는 memRead=0이라 false path입니다. 합성기가 이 경로를 `MemData` 신호를 거치지 않게 합쳐 놓아서, 위의 false path 제약을 빠져나갔습니다.

그래서 div/mul/add에서는 주소로 쓰이지 않는 비트(0, 1, 7~31)에 한해 `-through AluData[k] -through Mem_or_ALU[k]`로 같은 비트끼리 가는 경로만 따로 측정해 `T_direct`로 표기했습니다. 즉 ALU 결과 → MemToReg mux → RF 경로입니다.

## 결과: 원본 RTL (`syn/results/baseline/summary.txt`)

T_min (ns). 괄호 안은 `T_direct`입니다.

| mode | typ | slow | fast | 최악 경로 (시작 → 도착) |
|---|---:|---:|---:|---|
| none | **55.38** | 203.45 | 30.83 | PC → PC. 나눗셈기 → ALU 결과 → zero → 분기 mux (false path) |
| div | 54.79 (**54.03**) | 202.13 (198.86) | 30.45 (30.01) | PC → RF. RF 읽기 → 나눗셈기 → ALU 결과 → RF 쓰기 |
| mul | 7.50 (7.29) | 27.35 (25.55) | 4.45 (4.42) | PC → RF |
| add | 6.66 (6.03) | 23.22 (21.16) | 4.10 (3.73) | PC → PC (아래 한계 참고) |
| lw | 6.66 | 23.22 | 4.10 | PC → PC (아래 한계 참고) |
| sw | 6.78 | 24.01 | 4.11 | PC → 교환 버퍼 (주소 48 비교 → 버퍼 쓰기) |
| beq | 6.92 | 24.31 | 4.22 | PC → PC. 뺄셈 → ALU 결과 → zero → 분기 mux |

## 결과: zero 전용 비교기 변형 (`variants/zero_cmp.patch`, `syn/results/zero_cmp/summary.txt`)

`zero = (result == 0)`을 `zero = (A == B)`로 바꿨습니다.

- zero는 beq에서만 쓰입니다. beq일 때 ALU는 뺄셈이고 두 번째 피연산자는 레지스터 값이라서 기능은 같습니다.
- self-check TB로 확인한 결과, 50회 반복 전 구간의 결과, End까지 2,201 cycle, MUL/DIV/REC 횟수, 랜덤 초기값 3 seed가 모두 원본과 같았습니다.

| mode | typ | slow | fast | 원본 대비 (typ) |
|---|---:|---:|---:|---|
| none | 55.19 | 205.12 | 30.62 | 최악 경로의 도착점이 교환 버퍼로 바뀜: div → sw 주소 비교(==48) → 버퍼 쓰기 enable (또 다른 false path) |
| div | 54.57 (53.99) | 202.45 (199.97) | 30.33 (29.97) | 동일 수준 |
| mul | 7.36 (7.29) | 25.82 (25.48) | 4.43 (4.41) | 동일 수준 |
| add / lw / sw | 6.63 / 6.67 / 6.97 | 23.32 / 23.37 / 24.66 | 4.04 / 4.07 / 4.20 | 도착점이 RF/DMEM으로 정리됨 (원본의 PC 쪽 경로가 사라짐) |
| beq | **5.13** | **17.97** | **3.21** | **−1.79 ns (−26%)**. 분기 경로에서 ALU 결과 mux가 빠짐 |

## 개선: 나눗셈 → 역수 곱셈 (`variants/recip.patch`, `syn/results/recip/summary.txt`)

**왜 파이프라인보다 먼저 했나**: 원본 div 경로 54 ns 가운데 49 ns가 나눗셈기 한 블록입니다. 파이프라인의 클럭 주기는 가장 긴 단계로 정해지므로, CPU를 5단으로 나눠도 나눗셈기가 든 EX 단계가 약 50 ns로 남습니다. 그래서 알고리즘 쪽에서 나눗셈 자체를 없앴습니다.

**변경** (자코비의 `x = D⁻¹(b − Rx)` 형태)
- **데이터**: 각 코어 DMEM의 대각 원소 자리에 a_ii 대신 1/a_ii(Q15.16, 한 번 반올림: 6554 / 5461 / 4369 / 5958)를 저장합니다. DMEM 크기와 주소 배치는 그대로입니다.
- **프로그램**: 코어당 `div` 2개를 `mul`로 바꿉니다(funct `100011` → `100001`). 명령 수와 사이클 수는 같습니다.
- **하드웨어**: ALU에서 조합 나눗셈기를 제거합니다. 남겨 두면 쓰이지 않아도 STA가 그 경로를 봅니다.

**기능 검증** (`make check VARIANT=recip`, 골든 모델 `--recip`)
- 50회 반복 전 구간이 골든 모델과 일치하고, End까지 2,201 cycle로 원본과 같습니다.
- 코어당 MUL/DIV/REC = 400 / 0 / 50이고, 랜덤 초기값 3 seed 모두 PASS입니다.
- 결과는 x1..x3가 원본과 같고, x4만 9063 → 9064입니다. 정확한 해와의 오차는 0.75 → 0.25 LSB로 오히려 줄었고, 고정소수점 해가 멈추는 시점도 12회 → 11회로 당겨졌습니다.
- Verilator lint에서 `wide_dividend` LATCH 경고가 사라졌습니다.

**STA (typ, ns)**

| 경로 | 원본 | recip | recip + zero 비교기 |
|---|---:|---:|---:|
| 제약 없이 본 최악 경로 | 55.38 | **6.70** | 6.68 |
| 명령어별 최악 | 54.79 (div) | 6.44 (mul) | 6.43 (mul) |
| mul 직접 경로 | 7.29 | 5.86 | 5.94 |
| beq | 6.92 | 5.94 | 4.62 |
| cells / 면적 (µm²) | 34,849 / 50,386 | 21,848 / 34,322 | 21,795 / 34,259 |
| slow / fast (제약 없이 본 최악) | 203.45 / 30.83 | 24.12 / 4.04 | 24.06 / 4.08 |

recip 결과의 `div` 행은 의미가 없습니다. 나눗셈기를 제거해서 opcode 101은 0을 돌려줍니다.

**해석**
1. **8.3배**: 반복 1회 시간(44 cycle × 제약 없는 최악 경로)이 2.44 µs → 0.295 µs가 됩니다. 사이클 수와 정확도는 유지하면서 셀 37%, 면적 32%가 줄었습니다.
2. **zero 비교기 효과는 병목이 어디냐에 달렸습니다.** recip 위에 zero 비교기를 더하면 beq는 5.94 → 4.62 ns로 줄지만 최악 경로는 거의 그대로입니다. 병목이 mul과 주소 경로로 옮겨 갔기 때문입니다.
3. **새 최악 경로의 구성** (recip mul 직접 경로 5.86 ns 기준)
   - PC → 명령어 ROM 디코드: 약 2.7 ns (약 46%)
   - RF 읽기: 약 0.5 ns
   - 곱셈기: 약 1.7~2.3 ns
   - 제약 없는 최악 경로(6.70 ns)는 명령어별 최악(6.44 ns)보다 0.26 ns 깁니다. ALU 결과 → DMEM 쓰기 주소 경로(mul일 때 memWrite=0)라는 false path 때문입니다.
4. **다음 단계**
   - 이제는 한 블록이 사이클을 지배하지 않아서, **IF를 떼어내는 파이프라인이 효과를 볼 수 있는 구조**가 됐습니다.
   - 다만 이 흐름(Yosys+ABC)은 fanout 버퍼링과 게이트 사이징을 하지 않습니다. INV_X1 하나가 259개를 구동하는 식이라 ROM 디코드 지연이 부풀려져 있습니다. 파이프라인 분할 지점을 정하기 전에 버퍼링을 하는 흐름(예: OpenROAD `repair_design`)으로 다시 재는 게 먼저입니다.
   - → 아래 [OpenROAD 재측정](#버퍼링까지-한-재측정-openroad-synpnrtcl-synresultspnr_ptxt)에서 확인한 결과, 버퍼링 후에는 디코드 지연이 작아지고 병목은 곱셈기였습니다.

## 개선: 5단 파이프라인 (`variants/pipe/`, `syn/results/recip+pipe/`, `syn/results/recip+zero_cmp+pipe/`)

recip으로 나눗셈기가 빠진 뒤에는 한 블록이 사이클을 지배하지 않아서, 단계를 나누는 효과를 볼 수 있습니다.

**설계** (`variants/pipe/pipe_core.sv`, `processor_0/1.sv`만 교체)
- **단계와 재사용**: IF / ID / EX / MEM / WB입니다. 원본 `control_unit`, `alu_control`, `register_file`, `sign_extension`, `alu`는 그대로 씁니다.
- **해저드 처리**
  - forwarding: EX/MEM, MEM/WB → EX
  - bypass: WB → ID (레지스터 파일)
  - load-use: 1 cycle stall
  - `j`: ID에서 결정, 1개 flush
  - `beq`: EX에서 결정(predict not-taken), taken이면 2개 flush
  - r0: 하드와이어. 원본은 리셋 중 부수 효과에 의존했습니다.
- **`rec`의 순서 보장**: `rec`는 MEM 단계에서 상대 코어의 교환 버퍼를 DMEM[10:11]로 복사합니다. 두 코어가 같은 사이클에 같은 PC를 retire하므로(lockstep), 교환 버퍼를 쓰는 `sw`와 `rec`의 순서가 단일 사이클 설계와 같습니다. TB가 매 사이클 retire PC를 비교해 이 전제를 확인합니다.

**검증**
- TB는 `ifdef PIPE`에서 MEM/WB의 retire 포트를 기준으로 lockstep, fetch 범위, 이벤트 수를 셉니다.
- `recip+pipe`와 `pipe`(나눗셈기 포함 원본 프로그램) 모두 통과했습니다.
  - 50회 반복 전 구간이 골든 모델과 일치
  - End까지 2,556 cycle
  - 랜덤 초기값 10 seed PASS
- **랜덤 초기화로 찾은 버그**: 처음에는 랜덤 seed 5개 중 3개가 FAIL이었습니다.
  - 원인: 파이프라인 레지스터가 동기 리셋이라, 리셋 중 첫 클럭 엣지에서 `ex_mem_valid/memwrite/rec`가 아직 전원 인가 직후의 임의 값이었습니다. 그 값으로 DMEM 쓰기가 한 번 일어났습니다.
    - seed 1: `rec`가 DMEM1[10:11]을 덮어씀
    - seed 2: `sw`가 a12(DMEM0[1])와 b3(DMEM1[8])를 덮어씀
  - 수정: DMEM 쓰기, `rec`, RF 쓰기의 enable을 reset으로 qualify했습니다. 초기값을 0으로 두는 기본 시뮬레이션에서는 드러나지 않는 버그입니다.

**사이클**: 반복 1회가 44 → **51 cycle**이 됩니다. 늘어난 7 cycle의 구성은 다음과 같습니다.
- load-use stall 6개
  - `lw a11 → div`, `lw a22 → div`
  - `lw x(k+1) → sw` 2개
  - `lw counter → addi`
  - `lw limit → beq`
- `j` flush 1개

6개 stall은 명령 순서만 바꿔도(load를 앞당기기) 없앨 수 있어서, 이론상 45 cycle까지 줄어듭니다. 이 레포에는 적용하지 않았습니다.

**합성 직후 STA (typ, ideal clock, 배선 없음)**

| 설계 | T_min (ns) | 최악 경로 | cells / 면적 (µm²) |
|---|---:|---|---|
| recip (단일 사이클) | 6.70 | PC → ROM 디코드 → RF → 곱셈기 → … | 21,848 / 34,322 |
| recip + zero 비교기 | 6.68 | 〃 | 21,795 / 34,259 |
| recip + pipe | 4.24 | MEM/WB → forwarding mux → **곱셈기 → zero → 분기 판정** → ID/EX flush | 23,333 / 38,461 |
| recip + zero 비교기 + pipe | **3.53** | MEM/WB → forwarding mux → 곱셈기 → EX/MEM | 23,182 / 38,285 |

- **recip + pipe의 최악 경로는 false path입니다.** 단일 사이클에서 본 div → zero → PC와 같은 구조가 EX 단계 안에 다시 생겼습니다.
  - `zero`가 ALU 결과 mux 뒤에 있어서, 곱셈 결과가 분기 판정(`ex_taken`)까지 이어집니다.
  - 분기는 `beq`에서만 일어나고, `beq`는 뺄셈만 합니다.
  - zero 비교기(`A == B`)를 함께 적용하면 이 경로가 사라지고, 실제로 쓰이는 forwarding + 곱셈기 경로가 최악으로 남습니다.
- **파이프라인만으로는 주기가 1.9배(6.68 → 3.53 ns)만 줄었습니다.** EX 단계에 forwarding mux와 32×32 곱셈기가 함께 있기 때문입니다. 그다음 병목은 곱셈기이므로, 곱셈을 2단으로 나누거나 부분곱 트리를 개선하는 게 다음 순서입니다.
- **keep 속성이 결과에 영향을 줍니다.** 파이프라인 신호(`fwd_a/b`, `alu_result`, `ex_taken`, `stall` 등)에 `keep`을 걸면 경로 리포트에 어느 단계를 지나는지 찍힙니다. 대신 ABC가 그 경계를 넘어 최적화하지 못합니다.
  - 같은 recip + pipe가 keep 없이는 3.78 ns, keep을 걸면 4.24 ns였습니다.
  - 그래서 설계끼리 비교할 때는 아래 OpenROAD 결과(버퍼링·사이징 후)를 기준으로 합니다.

## 버퍼링까지 한 재측정: OpenROAD (`syn/pnr.tcl`, `syn/results/*/pnr_p*.txt`)

Yosys+ABC 넷리스트는 fanout 버퍼링과 게이트 사이징을 하지 않습니다. 그래서 셀 하나가 수백 개를 구동하고, 라이브러리의 max slew/cap 한계를 넘는 넷이 수백 개 생깁니다. 이 상태의 STA는 NLDM 테이블 범위 밖을 외삽해서 계산한 값이라 믿기 어렵습니다. 그래서 같은 넷리스트를 OpenROAD로 배치하고, 실제 흐름에서 하는 수리를 거친 뒤 다시 쟀습니다.

```
Yosys netlist ─> floorplan(40%) ─> global/detailed placement ─> wire RC(metal3) ─> repair_design ─> CTS ─> repair_timing
                                  STAGE placed                                  STAGE repair_design  STAGE cts  STAGE repair_timing
```

- **STAGE 줄**: 각 단계 뒤에 `T_min = 목표 주기 − worst slack`과, max slew / max cap 위반 개수(DRV)를 출력합니다.
- **분석 범위**: 명령어별 제약이 없는 구조적 최악 경로입니다. 그래서 zero 비교기를 적용한 설계끼리 비교할 때 가장 공정합니다(이때는 구조적 최악 경로가 실제 경로).
- **목표 주기**: repair_timing은 목표 주기를 향해 동작합니다. 그래서 모든 recip 계열 설계를 같은 목표 **2.0 ns**로 돌렸습니다.
  - 2.5 ns로 돌린 결과도 `pnr_p2.5.txt`로 남겨 두었습니다. recip + zero 비교기는 목표 2.5 → 2.73 ns, 2.0 → 2.77 ns로, 목표에 따라 ±1% 정도 흔들립니다.
  - 원본은 나눗셈기 경로가 40 ns대라, 목표를 40 ns로 두었습니다.
- **원본의 최악 경로**: 구조적 최악 경로(div → zero → PC, false path) 기준입니다. 실제 div 경로는 합성 직후 기준으로 1~2% 짧습니다.

**단계별 T_min (typ, ns)**

| 설계 | synth | placed | repair_design | cts | repair_timing | DRV (synth → repair_design 후) | 면적 (µm², 최종) |
|---|---:|---:|---:|---:|---:|---|---:|
| 원본 (목표 40 ns) | 55.38 | 60.56 | 44.46 | 44.46 | 41.79 | slew 317 / cap 489 → 0 / 1 | 57,295 |
| recip | 6.70 | 8.04 | 3.62 | 3.48 | 3.11 | slew 202 / cap 302 → 0 / 1 | 40,243 |
| recip + zero 비교기 | 6.68 | 8.12 | 3.40 | 3.26 | 2.77 | slew 196 / cap 316 → 0 / 2 | 39,573 |
| recip + pipe | 4.24 | 4.67 | 3.20 | 3.20 | 2.89 | slew 227 / cap 270 → 0 / 0 | 43,336 |
| recip + zero 비교기 + pipe | 3.53 | 3.87 | 2.95 | 2.95 | **2.39** | slew 152 / cap 235 → 0 / 2 | 43,772 |

**반복 1회 시간 (cycle × repair_timing 후 T_min)**

| 설계 | cycle/반복 | T_min | 반복 1회 | 원본 대비 |
|---|---:|---:|---:|---:|
| 원본 | 44 | 41.79 | 1,839 ns | 1× |
| recip + zero 비교기 | 44 | 2.77 | 121.7 ns | 15.1× |
| recip + zero 비교기 + pipe | 51 | 2.39 | 121.9 ns | 15.1× |
| (추정) 위 + 명령 재배치로 stall 제거 | 45 | 2.39 | 107.6 ns | 17.1× |

**해석**
1. **배치 전 수치는 방향조차 믿기 어렵습니다.**
   - 배선 RC가 붙으면 T_min이 늘어납니다: recip 기준 6.70 → 8.04 ns(+20%).
   - `repair_design`으로 slew/cap 위반을 0으로 만들면 크게 줄어듭니다: 8.04 → 3.62 ns.
   - 원본도 같은 방향입니다(60.56 → 44.46 ns). 나눗셈기 비중이 워낙 커서 줄어든 폭은 −27%입니다.
   - 단일 사이클 recip의 "ROM 디코드 2.7 ns"도 대부분 버퍼링이 안 된 fanout 때문이었습니다.
2. **파이프라인 효과가 합성 직후 예상보다 훨씬 작습니다.**
   - 합성 직후에는 주기가 1.9배(6.68 → 3.53 ns) 줄 것처럼 보였습니다.
   - 버퍼링과 사이징을 하고 나면 1.16배(2.77 → 2.39 ns)입니다. 단일 사이클 쪽이 "부풀려진 디코드"를 더 많이 돌려받았기 때문입니다.
   - 사이클이 44 → 51로 늘어난 것까지 넣으면, **반복 1회 시간은 단일 사이클과 비슷합니다**(121.7 vs 121.9 ns). 면적은 +11%입니다.
   - 명령 재배치로 stall 6개를 없애도(45 cycle) 이득은 1.13배(121.7 → 107.6 ns) 수준입니다.
3. **병목은 곱셈기입니다.**
   - 파이프라인의 최악 경로는 MEM/WB → forwarding mux → 32×32 곱셈기 → EX/MEM입니다.
   - 이 EX 단계 하나(2.39 ns)가 단일 사이클 전체 경로(2.77 ns)의 약 86%입니다. 버퍼링 후에는 fetch·decode·RF·write-back 쪽 지연이 작아서, 단계를 나눠도 줄어드는 몫이 적습니다.
   - 파이프라인이 효과를 보려면 곱셈기를 2단으로 나눠 EX 단계를 짧게 해야 합니다.
4. **판단 순서에 대한 교훈**: 합성 직후 수치(1.9배)만 보고 파이프라인 분할 지점을 정했다면 결론이 틀렸을 것입니다. 구조를 바꾸기 전에 버퍼링·배치까지 한 수치로 병목을 다시 확인해야 합니다.
5. **단일 사이클 설계의 최악 경로는 `reset` 입력에서 시작합니다.** repair_timing 후에 그렇습니다.
   - `reset`이 명령어(리셋 중 0 강제)와 RF 읽기(리셋 중 0)를 게이팅하기 때문에, 리셋 해제 사이클에 datapath 전체를 지납니다.
   - 입력 지연을 0으로 준 제약 기준이므로, 리셋 동기화 FF에서 나오는 실제 설계라면 clk→Q와 클럭 지연만큼 더 깁니다.

## 해석 (원본과 zero 비교기)

1. **Fmax는 나눗셈기가 결정합니다.** div 경로(직접 경로 54.0 ns)가 다음으로 긴 mul 경로(7.3 ns)의 7.4배입니다. 나눗셈을 여러 사이클로 나누거나, 상수인 `a_ii`로 나누는 대신 `1/a_ii`를 미리 구해 곱셈으로 바꾸면 Fmax를 크게 올릴 수 있습니다.
2. **false path가 최악 경로로 잡힙니다.** 여기서는 나눗셈기가 워낙 길어서 차이가 0.59 ns(1%)뿐입니다.
   - 하지만 div를 멀티사이클로 바꿔도 zero가 ALU 결과 mux 뒤에 있는 한, STA는 약 55 ns 경로를 계속 보고합니다.
   - 따라서 멀티사이클 제약(`set_multicycle_path`)이나 false path 제약을 명시하거나, 구조 자체를 분리해야 합니다.
3. **구조로 false path를 없앨 수 있습니다.** zero를 전용 비교기로 바꾸면 분기 경로에서 ALU 결과 mux가 빠져, beq가 26% 짧아집니다.
   - 다만 ALU 결과를 메모리 주소로도 같이 쓰기 때문에, div → 주소 비교 → 버퍼 쓰기라는 다음 false path가 남습니다.
   - 주소 계산기(AGU)를 ALU와 분리하면 이 경로도 없앨 수 있습니다.
4. **보고서의 2.624 ns는 최악 지연이 아닙니다.** 게이트 레벨 시뮬레이션에서 피연산자 하나(예: 2/15)로 관측한 지연이고, 나눗셈기 지연은 데이터에 따라 크게 달라집니다. 최대 동작 주파수의 근거로 쓸 수 없습니다.

## 한계

- **절대값**: Yosys의 범용 나눗셈 구현과 공개 라이브러리 기준입니다. 상용 합성(DesignWare 등)이면 나눗셈기가 더 빨라질 수 있고, 공정도 보고서와 다릅니다.
- **클럭과 배선**: ideal clock이고 배선 기생 성분이 없습니다. CTS 후 skew와 배선 지연이 더해지면 T_min은 늘어납니다.
- **명령어별 분석의 근사**: `ALUoperation`/`branch`를 상수로 고정하므로, PC → 명령어 ROM → 제어 디코드 → mux select 경로의 지연은 빠집니다.
- **원본 add/lw 모드**: 합성기가 zero 계산을 재구성해 ALU 결과 신호를 거치지 않고 PC로 가는 경로가 생겼고, 이 경로는 false path 제약에 걸리지 않았습니다. 그래서 이 값(6.66 ns, 도착점 PC)은 약간 비관적입니다. add의 직접 경로는 6.03 ns입니다.
- **재현성**: 새 디렉터리에서 `setup_tools.sh` → `flow.sh`로 처음부터 다시 돌렸고, 이전 실행과 같은 값이 나왔습니다.
- **OpenROAD 재측정**: typ 한 corner, 배치 기반 추정 RC(실제 라우팅 없음), 명령어별 제약 없는 구조적 분석입니다. 설계 간 상대 비교 용도이고, 실제 라우팅과 추출까지 하는 흐름은 `syn/cadence/`(Innovus + Tempus)에 준비해 두었습니다.

## 재현

```bash
make sta-tools                 # yosys, sv2v, OpenSTA(+CUDD) → build/tools (Ubuntu 24.04, root)
make sta                       # 원본: 합성 ~45분 + STA 21회 → syn/results/baseline/
make sta VARIANT=zero_cmp      # 변형 → syn/results/zero_cmp/
make sta VARIANT=recip         # 역수 곱셈 (나눗셈기가 없어 합성 수 분)
make check VARIANT=recip       # 변형 기능 검증 (골든 --recip)
make check VARIANT=recip+zero_cmp+pipe      # 5단 파이프라인 기능 검증
make sta VARIANT=recip+zero_cmp+pipe        # 합성 + 구조적 STA
make pnr-tools                              # OpenROAD (litex-hub conda) + Nangate45 LEF
make pnr VARIANT=recip+zero_cmp+pipe PERIOD=2   # 배치·수리 단계별 T_min → syn/results/<v>/pnr_p2.txt
```

`syn/results/<variant>/`에 들어가는 파일:
- `summary.txt`: corner·mode별 T_min, Fmax, 시작/도착 FF 그룹, 경로가 지나는 신호
- `stat.txt`: 셀 수와 면적
- `path_typ_{none,div,beq}.rpt`: 경로 전체 리포트
- `pnr_p<목표>.txt`, `pnr_p<목표>_path.rpt`: OpenROAD 단계별 T_min·DRV·면적, 최종 최악 경로
