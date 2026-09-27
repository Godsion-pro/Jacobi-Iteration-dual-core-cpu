`include "pipe_core.sv"
`include "instruction_memory_1.sv"
`include "data_memory_1.sv"

// variants/pipe: replaces the single-cycle processor_1 with the 5-stage pipe_core.
// Same ports as the original, so rtl/top.sv and syn/syn_top.sv are reused unchanged.
// The instruction ROM and data memory (with the exchange buffer / rec logic) are the
// original modules; only the core between them is new.
module processor_1 (
    input  logic clk,
    input  logic reset,
    exchange_if.core1 intf
);
    logic [31:0] imem_addr, imem_data;
    logic        dmem_read, dmem_write, dmem_rec;
    logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;

    pipe_core core (
        .clk(clk), .reset(reset),
        .imem_addr(imem_addr), .imem_data(imem_data),
        .dmem_read(dmem_read), .dmem_write(dmem_write), .dmem_rec(dmem_rec),
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata), .dmem_rdata(dmem_rdata),
        .ret_valid(), .ret_pc(), .ret_opcode(), .ret_aluop()
    );

    instruction_memory_1 instruction_memory (
        .address(imem_addr), .reset(reset), .instruction(imem_data)
    );

    data_memory_1 data_memory (
        .clk(clk), .rec(dmem_rec), .mem_read(dmem_read), .mem_write(dmem_write),
        .address(dmem_addr), .write_data(dmem_wdata), .read_data(dmem_rdata),
        .intf(intf)
    );
endmodule
