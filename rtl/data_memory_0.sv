module data_memory_0(
		     input logic	 clk, rec,
		     input logic	 mem_read,
		     input logic	 mem_write,
		     input logic [31:0]	 address,
		     input logic [31:0]	 write_data,
		     output logic [31:0] read_data,
		     exchange_if.core0   intf
		     );

   logic [31:0]				 Memory [0:17];


   always_comb begin
      if(mem_read)
	read_data = Memory[address[31:2]];
      else
	read_data = 32'h00000000;
   end

   always_ff @(posedge clk) begin
      if(mem_write) begin
			 Memory[address[31:2]] <= write_data;
					if(address == 48) begin
				    intf.buf0_to_1[0] <= write_data;
					end
					else if(address == 52) begin
				    intf.buf0_to_1[1] <= write_data;
					end
		  end // if (mem_write)
		  else if(rec) begin
			  Memory[10]         <= intf.buf1_to_0[0];
			  Memory[11]         <= intf.buf1_to_0[1];
			end
   end // always_ff @ (posedge clk)


endmodule // data_memory
