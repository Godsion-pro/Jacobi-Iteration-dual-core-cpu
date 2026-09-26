interface exchange_if;
  // core0 ↔ core1 데이터 교환을 위한 분리 버퍼
  logic [31:0] buf0_to_1 [0:1];  // core0이 쓰고 core1이 읽음 (x0, x1)
  logic [31:0] buf1_to_0 [0:1];  // core1이 쓰고 core0이 읽음 (x2, x3)

  // core0 모드포트: buf0_to_1은 output, buf1_to_0는 input
  modport core0 (
    output buf0_to_1,
    input  buf1_to_0
  );
  // core1 모드포트: buf1_to_0는 output, buf0_to_1는 input
  modport core1 (
    output buf1_to_0,
    input  buf0_to_1
  );
endinterface
