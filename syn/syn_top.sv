// Synthesis-only wrapper: same structure as rtl/top.sv, but exposes the exchange
// buffers as outputs so the synthesizer keeps the datapath (rtl/top.sv has no outputs).
module syn_top (
    input  logic        clk,
    input  logic        reset,
    output logic [31:0] buf0_to_1_0, buf0_to_1_1,
    output logic [31:0] buf1_to_0_0, buf1_to_0_1
);
    exchange_if intf();
    processor_0 i0 (.clk(clk), .reset(reset), .intf(intf.core0));
    processor_1 i1 (.clk(clk), .reset(reset), .intf(intf.core1));
    assign buf0_to_1_0 = intf.buf0_to_1[0];
    assign buf0_to_1_1 = intf.buf0_to_1[1];
    assign buf1_to_0_0 = intf.buf1_to_0[0];
    assign buf1_to_0_1 = intf.buf1_to_0[1];
endmodule
