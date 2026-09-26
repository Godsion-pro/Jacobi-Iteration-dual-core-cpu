`include "control_unit.sv"
`include "alu_control.sv"
`include "SCDP_without_control_unit_0.sv"

module processor_0 (
    input  logic clk,
    input  logic reset,
    exchange_if.core0 intf
);

    // Control Signals
    logic        RegDst;
    logic        RegWrite;
    logic        ALUsrc;
    logic        memRead;
    logic        memWrite;
    logic        MemToReg;
    logic        branch;
    logic        jump;
    logic rec;

    // 명령어 필드 및 ALU 관련 신호
    logic [5:0]  opcode;
    logic [5:0]  func;
    logic [2:0]  ALUoperation;
    logic [1:0]  ALUop;

    // Main Control Unit
    control_unit control_unit (
        .opcode    (opcode),
        .RegWrite  (RegWrite),
        .MemToReg  (MemToReg),
        .RegDst    (RegDst),
        .ALUsrc    (ALUsrc),
        .branch    (branch),
        .jump      (jump),
        .memWrite  (memWrite),
        .memRead   (memRead),
        .ALUop     (ALUop),
        .rec (rec)
    );

    // ALU Control Unit
    alu_control alu_control (
        .ALUop        (ALUop),
        .func         (func),
        .ALUoperation (ALUoperation)
    );

    // Single Cycle Datapath
    SCDP_without_control_unit_0 SCDP (
        .clk          (clk),
        .reset        (reset),
        .RegDst       (RegDst),
        .RegWrite     (RegWrite),
        .ALUsrc       (ALUsrc),
        .memRead      (memRead),
        .memWrite     (memWrite),
        .MemToReg     (MemToReg),
        .branch       (branch),
        .jump         (jump),
        .ALUoperation (ALUoperation),
        .opcode       (opcode),
        .func         (func),
        .intf         (intf),
        .rec (rec)
    );

endmodule
