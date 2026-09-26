module control_unit (
    input  logic [5:0] opcode,   // (instr_addr[31:26])

    output logic       RegWrite,
    output logic       MemToReg,
    output logic       RegDst,
    output logic       ALUsrc,
    output logic       branch,
    output logic       jump,
    output logic       memWrite,
    output logic       memRead,
    output logic [1:0] ALUop,
	  output logic       rec
);

    always_comb begin
        case (opcode)

            6'b000000 : begin // R_Type instruction
                RegWrite = 1;
                MemToReg = 0;
                RegDst   = 1;
                ALUsrc   = 0;
                branch   = 0;
                memWrite = 0;
                ALUop    = 2'b10;
                memRead  = 0;
                jump     = 0;
                rec = 0;
            end

            6'b100011 : begin  // load (lw) instruction
                RegWrite = 1;
                MemToReg = 1;
                RegDst   = 0;
                ALUsrc   = 1;
                branch   = 0;
                memWrite = 0;
                ALUop    = 2'b00;
                memRead  = 1;
                jump     = 0;
                rec = 0;
            end

            6'b101011 : begin  // store (sw) instruction
                RegWrite = 0;
                MemToReg = 'x;
                RegDst   = 'x;
                ALUsrc   = 1;
                branch   = 0;
                memWrite = 1;
                ALUop    = 2'b00;
                memRead  = 0;
                jump     = 0;
                rec = 0;
            end

            6'b000100, 6'b000101: begin  // beq, bne instruction
                RegWrite = 0;
                MemToReg = 'x;
                RegDst   = 'x;
                ALUsrc   = 0;
                branch   = 1;
                memWrite = 0;
                ALUop    = 2'b01;
                memRead  = 0;
                jump     = 0;
                rec = 0;
            end

            6'b001000 : begin  // addi instruction
                RegWrite = 1;
                MemToReg = 0;
                RegDst   = 0;
                ALUsrc   = 1;
                branch   = 0;
                memWrite = 0;
                ALUop    = 2'b00;
                memRead  = 0;
                jump     = 0;
                rec = 0;
            end

            6'b000010 : begin  // jump instruction
                RegWrite = 0;
                MemToReg = 'x;
                RegDst   = 'x;
                ALUsrc   = 'x;
                branch   = 0;
                memWrite = 0;
                ALUop    = 2'bxx;
                memRead  = 0;
                jump     = 1;
                rec = 0;
            end

            6'b010101 : begin  // recv instruction
                RegWrite = 0;
                MemToReg = 'x;
                RegDst   = 'x;
                ALUsrc   = 'x;
                branch   = 0;
                memWrite = 0;
                ALUop    = 2'bxx;
                memRead  = 0;
                jump     = 0;
                rec = 1;
            end

            default : begin
                RegWrite = 0;
                MemToReg = 'x;
                RegDst   = 'x;
                ALUsrc   = 'x;
                branch   = 0;
                memWrite = 0;
                ALUop    = 2'bxx;
                memRead  = 0;
                jump     = 0;
                rec = 0;
            end
        endcase
    end

endmodule
