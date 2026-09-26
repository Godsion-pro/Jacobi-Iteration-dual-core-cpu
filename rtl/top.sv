`include "processor_0.sv"
`include "processor_1.sv"
`include "exchange_if.sv"

module top(
    input logic clk,
    input logic reset
);

exchange_if intf();

processor_0 i0(
    .clk          (clk),
    .reset        (reset),
    .intf         (intf.core0)
);

processor_1 i1(
    .clk          (clk),
    .reset        (reset),
    .intf         (intf.core1)
);
endmodule
