`include "program_counter.sv"
`include "pc_adder.sv"
`include "instruction_memory_0.sv"


module instruction_fetch_0 (
    input  logic        clk,
    input  logic        reset,
    input  logic        zero,
    input  logic        branch,
    input  logic        jump,
    input  logic [31:0] offset,
    output logic [31:0] instruction
);

    // 내부 신호
    logic [31:0] PC_address;
    logic [31:0] PC_plus_4;
    logic [31:0] Branch_Address;
    logic [31:0] Actual_PC_Address;
    logic [31:0] BTA;
    logic [31:0] JTA;

    // Program Counter
    program_counter program_counter (
        .PC_next(Actual_PC_Address),
        .clk(clk),
        .reset(reset),
        .PC(PC_address)
    );

    // PC + 4 계산기
    pc_adder pc_adder (
        .PC_address(PC_address),
        .PC_plus_4(PC_plus_4)
    );

    // 명령어 메모리
    instruction_memory_0 instruction_memory (
        .address(PC_address),
        .reset(reset),
        .instruction(instruction)
    );

    // 분기 주소 계산 (BTA = PC+4 + (offset << 2))
    assign BTA = PC_plus_4 + (offset << 2);

    // 점프 주소 계산 (JTA = {PC+4[31:28], instruction[25:2], 2'b00})
    assign JTA = {PC_plus_4[31:28], instruction[25:2], 2'b00};

    // Branch MUX: zero & branch → BTA, else → PC+4
    assign Branch_Address = (zero && branch) ? BTA : PC_plus_4;

    // Jump MUX: jump → JTA, else → Branch_Address
    assign Actual_PC_Address = jump ? JTA : Branch_Address;

endmodule
