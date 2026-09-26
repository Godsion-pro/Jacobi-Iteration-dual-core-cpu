`timescale 1ns/1ns
`include "top.sv"

// Self-checking testbench.
// Added during the 2026 portfolio cleanup; NOT part of the original course submission
// (the original stimulus-only testbench is tb/top_tb.sv).
//
// Same stimulus as tb/top_tb.sv, plus:
//   1. per-iteration comparison of x1..x4 against the bit-exact golden model
//      (model/jacobi_golden.py -> build/golden_expected.svh)
//   2. exchange check: each core's received copy (Memory[10..11]) == peer's result
//   3. lockstep assertion: both cores fetch the same PC every cycle
//      (the rec-based exchange has no handshake and relies on this)
//   4. fetch-range assertion: PC never leaves the 46-word instruction memory
//   5. termination check: PC parks at End (byte address 180)
//   6. MUL / DIV / REC event counters per core
module top_tb_selfcheck;
   logic clk   = 1'b0;
   logic reset = 1'b0;            // active-low

   top top (.clk(clk), .reset(reset));

   always #5 clk = ~clk;          // 100 MHz testbench clock

`include "golden_expected.svh"    // GOLDEN_ITERS, golden[k][0:3]

   localparam int PC_END     = 180;   // "End: j End"
   localparam int PC_LAST    = 45*4;  // last valid instruction address
   localparam int MAX_CYCLES = 20000;

   wire [31:0] pc0  = top.i0.SCDP.instruction_fetch.PC_address;
   wire [31:0] pc1  = top.i1.SCDP.instruction_fetch.PC_address;
   wire [5:0]  op0  = top.i0.opcode;
   wire [5:0]  op1  = top.i1.opcode;
   wire [2:0]  alu0 = top.i0.ALUoperation;
   wire [2:0]  alu1 = top.i1.ALUoperation;

   int errors = 0, assert_fail = 0;
   int cycles = 0, end_cycle = -1, park = 0;
   int iters_seen = 0, last_beq = -1, cpi_min = 1 << 30, cpi_max = 0;
   int mul_cnt [2] = '{0, 0};
   int div_cnt [2] = '{0, 0};
   int rec_cnt [2] = '{0, 0};

   // ---------------- stimulus (identical to tb/top_tb.sv) ----------------
   initial begin
      top.i0.SCDP.data_memory.Memory[17] = GOLDEN_ITERS;  // loop limit
      top.i0.SCDP.data_memory.Memory[10] = 0;             // x3(0)
      top.i0.SCDP.data_memory.Memory[11] = 0;             // x4(0)
      top.i0.SCDP.data_memory.Memory[12] = 0;             // x1(0)
      top.i0.SCDP.data_memory.Memory[13] = 0;             // x2(0)
      top.i0.SCDP.data_memory.Memory[0]  = 10*65536;      // a11
      top.i0.SCDP.data_memory.Memory[1]  =  1*65536;      // a12
      top.i0.SCDP.data_memory.Memory[2]  =  2*65536;      // a13
      top.i0.SCDP.data_memory.Memory[3]  =  1*65536;      // a14
      top.i0.SCDP.data_memory.Memory[4]  =  2*65536;      // a21
      top.i0.SCDP.data_memory.Memory[5]  = 12*65536;      // a22
      top.i0.SCDP.data_memory.Memory[6]  =  1*65536;      // a23
      top.i0.SCDP.data_memory.Memory[7]  =  2*65536;      // a24
      top.i0.SCDP.data_memory.Memory[8]  =  2*65536;      // b1
      top.i0.SCDP.data_memory.Memory[9]  =  2*65536;      // b2

      top.i1.SCDP.data_memory.Memory[17] = GOLDEN_ITERS;
      top.i1.SCDP.data_memory.Memory[10] = 0;             // x1(0)
      top.i1.SCDP.data_memory.Memory[11] = 0;             // x2(0)
      top.i1.SCDP.data_memory.Memory[12] = 0;             // x3(0)
      top.i1.SCDP.data_memory.Memory[13] = 0;             // x4(0)
      top.i1.SCDP.data_memory.Memory[0]  =  1*65536;      // a31
      top.i1.SCDP.data_memory.Memory[1]  =  1*65536;      // a32
      top.i1.SCDP.data_memory.Memory[2]  = 15*65536;      // a33
      top.i1.SCDP.data_memory.Memory[3]  =  1*65536;      // a34
      top.i1.SCDP.data_memory.Memory[4]  =  1*65536;      // a41
      top.i1.SCDP.data_memory.Memory[5]  =  2*65536;      // a42
      top.i1.SCDP.data_memory.Memory[6]  =  1*65536;      // a43
      top.i1.SCDP.data_memory.Memory[7]  = 11*65536;      // a44
      top.i1.SCDP.data_memory.Memory[8]  =  2*65536;      // b3
      top.i1.SCDP.data_memory.Memory[9]  =  2*65536;      // b4

      #20 reset = 1'b1;            // hold reset over two rising edges, then release
   end

`ifdef TRACE
   initial begin
      $dumpfile("build/wave.vcd");
      $dumpvars(0, top_tb_selfcheck);
   end
`endif

   // ---------------- invariants (checked every cycle after reset) ----------------
   // Written as clocked if-checks: Verilator 5.020 miscompiles counter updates inside
   // assertion action blocks. Only the first 5 violations are printed.
   task automatic violation(string name, int a, int b);
      assert_fail = assert_fail + 1;
      if (assert_fail <= 5) $display("ASSERT %s: pc0=%0d pc1=%0d", name, a, b);
   endtask

   always @(posedge clk) if (reset) begin
      if (pc0 != pc1)                          violation("a_lockstep (PC differs)", pc0, pc1);
      if (pc0 > PC_LAST || pc1 > PC_LAST)      violation("a_fetch_range (PC outside IMEM)", pc0, pc1);
   end

   // ---------------- monitors ----------------
   function automatic void check_word(string what, int k, int got, int exp);
      if (got !== exp) begin
         errors = errors + 1;
         if (errors <= 10)
            $display("MISMATCH iter %0d %s: got %0d expected %0d", k, what, got, exp);
      end
   endfunction

   always @(posedge clk) if (reset) begin
      cycles = cycles + 1;

      if (alu0 == 3'b011) mul_cnt[0] = mul_cnt[0] + 1;
      if (alu1 == 3'b011) mul_cnt[1] = mul_cnt[1] + 1;
      if (alu0 == 3'b101) div_cnt[0] = div_cnt[0] + 1;
      if (alu1 == 3'b101) div_cnt[1] = div_cnt[1] + 1;
      if (op0 == 6'b010101) rec_cnt[0] = rec_cnt[0] + 1;
      if (op1 == 6'b010101) rec_cnt[1] = rec_cnt[1] + 1;

      // end of one Jacobi iteration: the loop-exit beq (after update, rec and counter++)
      if (op0 == 6'b000100) begin
         automatic int k = top.i0.SCDP.data_memory.Memory[16];
         iters_seen = iters_seen + 1;
         if (last_beq >= 0) begin
            if (cycles - last_beq < cpi_min) cpi_min = cycles - last_beq;
            if (cycles - last_beq > cpi_max) cpi_max = cycles - last_beq;
         end
         last_beq = cycles;
         if (k < 1 || k > GOLDEN_ITERS) begin
            errors = errors + 1;
            $display("ERROR loop counter out of range: %0d", k);
         end else begin
            check_word("core0 x1",           k, top.i0.SCDP.data_memory.Memory[12], golden[k][0]);
            check_word("core0 x2",           k, top.i0.SCDP.data_memory.Memory[13], golden[k][1]);
            check_word("core1 x3",           k, top.i1.SCDP.data_memory.Memory[12], golden[k][2]);
            check_word("core1 x4",           k, top.i1.SCDP.data_memory.Memory[13], golden[k][3]);
            check_word("core0 recv x3",      k, top.i0.SCDP.data_memory.Memory[10], golden[k][2]);
            check_word("core0 recv x4",      k, top.i0.SCDP.data_memory.Memory[11], golden[k][3]);
            check_word("core1 recv x1",      k, top.i1.SCDP.data_memory.Memory[10], golden[k][0]);
            check_word("core1 recv x2",      k, top.i1.SCDP.data_memory.Memory[11], golden[k][1]);
         end
      end

      if (pc0 == PC_END && pc1 == PC_END) begin
         if (end_cycle < 0) end_cycle = cycles;
         park = park + 1;
      end

      if (park == 5 || cycles == MAX_CYCLES) finish_report();
   end

   function automatic real q2r(int v);
      return real'(v) / 65536.0;
   endfunction

   task automatic finish_report();
      int x [4];
      x[0] = top.i0.SCDP.data_memory.Memory[12];
      x[1] = top.i0.SCDP.data_memory.Memory[13];
      x[2] = top.i1.SCDP.data_memory.Memory[12];
      x[3] = top.i1.SCDP.data_memory.Memory[13];

      if (end_cycle < 0) begin
         errors = errors + 1;
         $display("ERROR never reached End (PC=%0d) within %0d cycles", PC_END, MAX_CYCLES);
      end
      if (iters_seen != GOLDEN_ITERS) begin
         errors = errors + 1;
         $display("ERROR iterations seen %0d, expected %0d", iters_seen, GOLDEN_ITERS);
      end
      for (int c = 0; c < 2; c++) begin
         if (mul_cnt[c] != 6*GOLDEN_ITERS || div_cnt[c] != 2*GOLDEN_ITERS || rec_cnt[c] != GOLDEN_ITERS) begin
            errors = errors + 1;
            $display("ERROR core%0d event count MUL/DIV/REC = %0d/%0d/%0d, expected %0d/%0d/%0d",
                     c, mul_cnt[c], div_cnt[c], rec_cnt[c], 6*GOLDEN_ITERS, 2*GOLDEN_ITERS, GOLDEN_ITERS);
         end
      end
      for (int i = 0; i < 4; i++) check_word($sformatf("final x%0d", i + 1), GOLDEN_ITERS, x[i], golden[GOLDEN_ITERS][i]);

      $display("==================== dual-core Jacobi self-check ====================");
      $display("iterations          : %0d (golden %0d)", iters_seen, GOLDEN_ITERS);
      $display("cycles / iteration  : min %0d, max %0d", cpi_min, cpi_max);
      $display("cycles to End       : %0d (reset release -> PC=%0d)", end_cycle, PC_END);
      $display("MUL/DIV/REC core0   : %0d / %0d / %0d", mul_cnt[0], div_cnt[0], rec_cnt[0]);
      $display("MUL/DIV/REC core1   : %0d / %0d / %0d", mul_cnt[1], div_cnt[1], rec_cnt[1]);
      for (int i = 0; i < 4; i++)
         $display("x%0d                  : %0d (%.8f)  golden %0d", i + 1, x[i], q2r(x[i]), golden[GOLDEN_ITERS][i]);
      $display("check errors        : %0d", errors);
      $display("assertion failures  : %0d", assert_fail);
      if (errors == 0 && assert_fail == 0) begin
         $display("RESULT: PASS");
         $finish;
      end else begin
         $display("RESULT: FAIL");
         $fatal(1, "self-check failed");
      end
   endtask
endmodule
