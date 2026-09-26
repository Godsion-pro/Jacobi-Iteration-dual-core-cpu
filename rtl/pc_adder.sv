module pc_adder (
    input  logic [31:0] PC_address,
    output logic [31:0] PC_plus_4
);

    // PC + 4 계산
    assign PC_plus_4 = PC_address + 32'd4;

endmodule
