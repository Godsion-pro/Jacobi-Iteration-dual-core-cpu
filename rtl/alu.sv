module alu (
    input  logic signed [31:0] A,
    input  logic signed [31:0] B,
    input  logic [2:0]  ALU_operation,
    output logic        zero,
    output logic signed [31:0] result
);

// 내부 연산용 와이드 변수
   logic signed [63:0]	       wide_mul;
   logic signed [63:0]	       wide_dividend;

    always_comb begin
        // 기본값 설정
        result = 32'd0;

        // ALU 연산 선택
        case (ALU_operation)
            3'b000: result = A & B;                      // AND
            3'b001: result = A | B;                      // OR
            3'b010: result = A + B;                      // ADD
            3'b110: result = A - B;                      // SUB
	    3'b011: begin                                // MUL
	       wide_mul = A * B;

	       result   = wide_mul >>> 16;
	    end
	    3'b101: begin                                // DIV
	       if (B == 0) begin
	          result = 32'sd0;
	          //error  = 1;
	       end else begin
                // 나눗셈: (a << 16) / b  → Q15.16 유지
	          wide_dividend = A <<< 16;
	          result = wide_dividend / B;
	       end
	    end
            3'b111: result = (A < B) ? 32'd1 : 32'd0;    // SLT
            default: result = 32'd0;
        endcase

        // zero 플래그 설정 (BEQ, BNE 용)
        zero = (result == 32'd0);
    end

endmodule
