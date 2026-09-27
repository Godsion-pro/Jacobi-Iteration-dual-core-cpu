# STA 재분석 (2026, 프로젝트 종료 후 추가 연구)

과제 보고서에는 "div 명령 지연 2.624 ns, 추정 최대 클럭 약 375 MHz"라고 적었습니다. 이 값은 게이트 레벨 시뮬레이션에서 div 명령 1건을 관측한 것이라, 정적 타이밍 분석(STA) 기준의 Fmax라고 할 수 없습니다. 그래서 원본 RTL을 공개 툴체인으로 다시 합성하고 STA를 했습니다.

셀 라이브러리가 보고서와 달라 **절대값은 비교 대상이 아닙니다.** 이 분석으로 확인하려는 것은 세 가지입니다.

1. 크리티컬 패스가 어디인지
2. false path가 STA 결과를 어떻게 부풀리는지
3. 구조 개선이 실제로 효과가 있는지

## 요약 (Nangate45 typical)

| 항목 | 결과 |
|---|---|
| Fmax를 결정하는 경로 | div → RF, **54.79 ns → Fmax 18.3 MHz**. 조합 64비트 나눗셈기 |
| div를 제외했을 때 다음 병목 | mul → RF, 7.50 ns (133 MHz) |
| 제약 없이 본 최악 경로 | div → ALU 결과 → zero → 분기 mux → PC, 55.38 ns. div 실행 중에는 branch=0이라 **실제로 쓰이지 않는 경로(false path)** |
| 개선안: zero를 전용 비교기로 분리 | beq 경로 **6.92 → 5.14 ns (−26%)**. self-check TB에서 기능 동일 확인 |
| 보고서 2.624 ns | 45 nm typ에서도 나눗셈기 최악 지연이 약 55 ns. 특정 피연산자에서 관측한 값으로 판단 |

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

## 결과: 원본 RTL (`syn/results/baseline/summary.txt`)

T_min (ns). 괄호 안은 경로의 시작 → 도착 FF 그룹입니다.

| mode | typ | slow | fast | 경로 |
|---|---:|---:|---:|---|
| none | **55.38** | 203.45 | 30.83 | PC → PC. ALU 결과 → zero → 분기 mux (false path) |
| div | **54.79** | 202.13 | 30.45 | PC → RF. RF 읽기 → 나눗셈기 → ALU 결과 → MemToReg mux |
| mul | 7.50 | 27.35 | 4.45 | PC → RF |
| sw | 6.78 | 24.01 | 4.11 | PC → DMEM |
| add / lw | 6.66 | 23.22 | 4.10 | PC → PC (아래 한계 참고) |
| beq | 6.92 | 24.31 | 4.22 | PC → PC. 뺄셈 → ALU 결과 → zero → 분기 mux |

## 결과: zero 전용 비교기 변형 (`syn/patches/zero_cmp.patch`, `syn/results/zero_cmp/summary.txt`)

`zero = (result == 0)`을 `zero = (A == B)`로 바꿨습니다.

- zero는 beq에서만 쓰입니다. beq일 때 ALU는 뺄셈이고 두 번째 피연산자는 레지스터 값이라서 기능은 같습니다.
- self-check TB로 확인한 결과, 50회 반복 전 구간의 결과, End까지 2,201 cycle, MUL/DIV/REC 횟수, 랜덤 초기값 3 seed가 모두 원본과 같았습니다.

| mode | typ | slow | fast | 원본 대비 (typ) |
|---|---:|---:|---:|---|
| none | 55.19 | 205.12 | 30.62 | 최악 경로의 도착점이 교환 버퍼로 바뀜: div → sw 주소 비교(==48) → 버퍼 쓰기 enable (또 다른 false path) |
| div | 54.57 | 202.45 | 30.33 | 동일 수준 |
| mul | 7.36 | 25.82 | 4.44 | 동일 수준 |
| beq | **5.14** | **17.97** | **3.21** | **−1.78 ns (−26%)**. 분기 경로에서 ALU 결과 mux가 빠짐 |

## 해석

1. **Fmax는 나눗셈기가 결정합니다.** div 경로(54.8 ns)가 다음으로 긴 mul 경로(7.5 ns)의 7.3배입니다. 나눗셈을 여러 사이클로 나누거나, 상수인 `a_ii`로 나누는 대신 `1/a_ii`를 미리 구해 곱셈으로 바꾸면 Fmax를 크게 올릴 수 있습니다.
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
- **원본 add/lw 모드**: 합성기가 zero 계산을 재구성해 ALU 결과 신호를 거치지 않고 PC로 가는 경로가 생겼고, 이 경로는 false path 제약에 걸리지 않았습니다. 그래서 이 값(6.66 ns, 도착점 PC)은 약간 비관적입니다.

## 재현

```bash
make sta-tools                 # yosys, sv2v, OpenSTA(+CUDD) → build/tools (Ubuntu 24.04, root)
make sta                       # 원본: 합성 ~45분 + STA 21회 → syn/results/baseline/
make sta VARIANT=zero_cmp      # 변형 → syn/results/zero_cmp/
```

`syn/results/<variant>/`에 들어가는 파일:
- `summary.txt`: corner·mode별 T_min, Fmax, 시작/도착 FF 그룹, 경로가 지나는 신호
- `stat.txt`: 셀 수와 면적
- `path_typ_{none,div,beq}.rpt`: 경로 전체 리포트
