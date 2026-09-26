module alu_control (
    input  logic [1:0] ALUop,
    input  logic [5:0] func, // funct field (instr_addr[5:0])
    output logic [2:0] ALUoperation
);

    always_comb begin
        unique casex (ALUop)

            2'b00: begin // LOAD/STORE
                ALUoperation = 3'b010; // add
            end

            2'b01: begin // BEQ
                ALUoperation = 3'b110; // subtract
            end

            2'b10: begin // R_TYPE
                unique case (func)
                    6'b100000: ALUoperation = 3'b010; // add
                    6'b100010: ALUoperation = 3'b110; // subtract
                    6'b100100: ALUoperation = 3'b000; // and
                    6'b100101: ALUoperation = 3'b001; // or
                    6'b100001: ALUoperation = 3'b011; // mul
                    6'b100011: ALUoperation = 3'b101; // div
                    6'b101010: ALUoperation = 3'b111; // set less than (SLT)

                    default:   ALUoperation = 3'bxxx;
                endcase
            end

            default: ALUoperation = 3'bxxx;

        endcase
    end

endmodule
