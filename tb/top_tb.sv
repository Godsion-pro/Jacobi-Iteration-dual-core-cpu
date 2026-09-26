`timescale 1ns/1ns
`include "top.sv"

module top_tb;
   logic clk;
   logic reset;

   top top (/*AUTOINST*/
	    // Inputs
	    .clk			(clk),
	    .reset			(reset));

   always
     #5 clk <= ~clk;

   initial begin
      top.i0.SCDP.data_memory.Memory[17] = 50; //

      top.i0.SCDP.data_memory.Memory[10] = 0; //x3
      top.i0.SCDP.data_memory.Memory[11] = 0; //x4

      top.i0.SCDP.data_memory.Memory[12] = 0; //x1
      top.i0.SCDP.data_memory.Memory[13] = 0; //x2

      top.i0.SCDP.data_memory.Memory[0] = 10*65536; //a11
      top.i0.SCDP.data_memory.Memory[1] = 1*65536; //a12
      top.i0.SCDP.data_memory.Memory[2] = 2*65536; //a13
      top.i0.SCDP.data_memory.Memory[3] = 1*65536; //a14
      top.i0.SCDP.data_memory.Memory[4] = 2*65536; //a21
      top.i0.SCDP.data_memory.Memory[5] = 12*65536; //a22
      top.i0.SCDP.data_memory.Memory[6] = 1*65536; //a23
      top.i0.SCDP.data_memory.Memory[7] = 2*65536; //a24

      top.i0.SCDP.data_memory.Memory[8] = 2*65536; //b1
      top.i0.SCDP.data_memory.Memory[9] = 2*65536; //b2



      top.i1.SCDP.data_memory.Memory[17] = 50; //

      top.i1.SCDP.data_memory.Memory[10] = 0; //x1
      top.i1.SCDP.data_memory.Memory[11] = 0; //x2

      top.i1.SCDP.data_memory.Memory[12] = 0; //x3
      top.i1.SCDP.data_memory.Memory[13] = 0; //x4

      top.i1.SCDP.data_memory.Memory[0] = 1*65536; //a31
      top.i1.SCDP.data_memory.Memory[1] = 1*65536; //a32
      top.i1.SCDP.data_memory.Memory[2] = 15*65536; //a33
      top.i1.SCDP.data_memory.Memory[3] = 1*65536; //a34
      top.i1.SCDP.data_memory.Memory[4] = 1*65536; //a41
      top.i1.SCDP.data_memory.Memory[5] = 2*65536; //a42
      top.i1.SCDP.data_memory.Memory[6] = 1*65536; //a43
      top.i1.SCDP.data_memory.Memory[7] = 11*65536; //a44
      top.i1.SCDP.data_memory.Memory[8] = 2*65536; //b3
      top.i1.SCDP.data_memory.Memory[9] = 2*65536; //b4



      clk = 0;
      #10 reset = 0;
      #10 reset = 1;

      #50000
	$finish();

   end // initial begin

endmodule // processor_tb
