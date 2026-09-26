module program_counter (
			 input logic	     clk,
			 input logic	     reset,
			 input logic [31:0]  PC_next,
			 output logic [31:0] PC
			);

   always_ff @(posedge clk) begin
      if (!reset)
        PC <= 32'h00000000;
      else
        PC <= PC_next;
   end

endmodule
