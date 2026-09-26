`include "instruction_fetch_0.sv"
`include "register_file.sv"
`include "sign_extension.sv"
`include "alu.sv"
`include "data_memory_0.sv"


module SCDP_without_control_unit_0 (
    input  logic        clk,
    input  logic        reset,
    input  logic        RegDst,
    input  logic        RegWrite,
    input  logic        ALUsrc,
    input  logic        memRead,
    input  logic        memWrite,
    input  logic        MemToReg,
    input  logic        branch,
    input  logic        jump,
    input  logic [2:0]  ALUoperation,
    output logic [5:0]  opcode,
    output logic [5:0]  func,
    exchange_if.core0 intf,  // [compat] explicit modport (Verilator 5.x rejects generic port + modport connection)
    input logic rec
);

    // internal wires
    logic        zero;
    logic [4:0]  write_register;
    logic [31:0] instruction;
    logic [31:0] read_data_1, read_data_2;
    logic [31:0] operand_32;
    logic [31:0] ALU_operand2;
    logic [31:0] AluData;
    logic [31:0] MemData;
    logic [31:0] Mem_or_ALU;

    // instruction fetch unit
    instruction_fetch_0 instruction_fetch (
        .reset(reset),
        .clk(clk),
        .zero(zero),
        .branch(branch),
        .jump(jump),
        .offset(operand_32),
        .instruction(instruction)
    );

    // opcode, func
    assign opcode = instruction[31:26];
    assign func   = instruction[5:0];

    // RegDst  MUX
    assign write_register = (RegDst == 1'b0) ? instruction[20:16] : instruction[15:11];

    // Register File
    register_file register_file (
        .register_read_1 (instruction[25:21]),
        .register_read_2 (instruction[20:16]),
        .write_register  (write_register),
        .write_data      (Mem_or_ALU),
        .reg_write       (RegWrite),
        .clk             (clk),
        .reset           (reset),
        .read_data_1     (read_data_1),
        .read_data_2     (read_data_2)
    );

    // sign-extension
    sign_extension sign_extension (
        .input_16  (instruction[15:0]),
        .output_32 (operand_32)
    );

    // ALU operand MUX
    assign ALU_operand2 = (ALUsrc == 1'b0) ? read_data_2 : operand_32;

    // ALU
    alu alu (
        .A             (read_data_1),
        .B             (ALU_operand2),
        .ALU_operation (ALUoperation),
        .zero          (zero),
        .result        (AluData)
    );

    // Data Memory
    data_memory_0 data_memory (
        .address     (AluData),
        .write_data  (read_data_2),
        .mem_read    (memRead),
        .clk         (clk),
        .mem_write   (memWrite),
        .read_data   (MemData),
        .intf         (intf),
        .rec (rec)
    );

    // Mem or ALU MUX
    assign Mem_or_ALU = (MemToReg == 1'b1) ? MemData : AluData;

endmodule
