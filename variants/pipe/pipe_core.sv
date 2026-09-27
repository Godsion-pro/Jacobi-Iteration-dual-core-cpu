`include "control_unit.sv"
`include "alu_control.sv"
`include "register_file.sv"
`include "sign_extension.sv"
`include "alu.sv"

// 5-stage pipelined version of the single-cycle core (IF / ID / EX / MEM / WB).
// Added in the 2026 follow-up study (variants/pipe); reuses the original control_unit,
// alu_control, register_file, sign_extension and alu modules unchanged.
//
//  - forwarding : EX/MEM and MEM/WB -> EX operands; WB -> ID through a register-file bypass
//  - load-use   : 1-cycle stall (bubble into ID/EX, IF and IF/ID hold)
//  - j          : resolved in ID, 1 flushed fetch
//  - beq        : resolved in EX, predict not-taken, 2 flushed instructions when taken
//  - $zero      : r0 reads as 0 and is never written (the single-cycle core relied on a
//                 reset-time side effect for this, which a pipeline does not reproduce)
//  - memories stay outside (processor_0/1): IMEM read is combinational in IF,
//    DMEM read is combinational in MEM and writes at the end of MEM
//  - write enables (DMEM write / rec, RF write) are qualified with reset: the pipeline
//    registers reset synchronously, so at the first edge under reset they still hold their
//    power-up state and could otherwise write DMEM (seen with randomized initial state)
module pipe_core (
    input  logic        clk,
    input  logic        reset,          // active-low

    output logic [31:0] imem_addr,
    input  logic [31:0] imem_data,

    output logic        dmem_read,
    output logic        dmem_write,
    output logic        dmem_rec,
    output logic [31:0] dmem_addr,
    output logic [31:0] dmem_wdata,
    input  logic [31:0] dmem_rdata,

    // retire port (MEM/WB): used only by the testbench
    output logic        ret_valid,
    output logic [31:0] ret_pc,
    output logic [5:0]  ret_opcode,
    output logic [2:0]  ret_aluop
);

    // ------------------------------------------------------------ pipeline registers
    // IF/ID
    logic        if_id_valid;
    logic [31:0] if_id_pc, if_id_instr;
    // ID/EX
    logic        id_ex_valid, id_ex_regwrite, id_ex_memtoreg, id_ex_memread, id_ex_memwrite;
    logic        id_ex_branch, id_ex_rec, id_ex_alusrc;
    logic [2:0]  id_ex_aluop;
    logic [4:0]  id_ex_rs, id_ex_rt, id_ex_wr;
    logic [31:0] id_ex_pc, id_ex_rd1, id_ex_rd2, id_ex_imm;
    logic [5:0]  id_ex_opcode;
    // EX/MEM
    logic        ex_mem_valid, ex_mem_regwrite, ex_mem_memtoreg, ex_mem_memread, ex_mem_memwrite, ex_mem_rec;
    logic [4:0]  ex_mem_wr;
    logic [31:0] ex_mem_pc, ex_mem_alu, ex_mem_store;
    logic [5:0]  ex_mem_opcode;
    logic [2:0]  ex_mem_aluop;
    // MEM/WB
    logic        mem_wb_valid, mem_wb_regwrite, mem_wb_memtoreg;
    logic [4:0]  mem_wb_wr;
    logic [31:0] mem_wb_pc, mem_wb_alu, mem_wb_mem;
    logic [5:0]  mem_wb_opcode;
    logic [2:0]  mem_wb_aluop;

    // ------------------------------------------------------------ hazard / redirect signals
    logic        stall;          // load-use
    logic        id_jump;        // j in ID
    logic [31:0] id_jta;
    logic        ex_taken;       // beq taken in EX
    logic [31:0] ex_bta;

    // ------------------------------------------------------------ WB (needed by ID bypass)
    logic [31:0] wb_data;
    logic        wb_we;
    assign wb_data = mem_wb_memtoreg ? mem_wb_mem : mem_wb_alu;
    assign wb_we   = reset && mem_wb_valid && mem_wb_regwrite && (mem_wb_wr != 5'd0);

    // ============================================================ IF
    logic [31:0] pc, pc_next;
    assign imem_addr = pc;
    assign pc_next   = ex_taken ? ex_bta : (id_jump ? id_jta : pc + 32'd4);

    always_ff @(posedge clk) begin
        if (!reset)      pc <= 32'd0;
        else if (!stall) pc <= pc_next;
    end

    always_ff @(posedge clk) begin
        if (!reset || ex_taken || id_jump) begin
            if_id_valid <= 1'b0;
            if_id_instr <= 32'd0;
            if_id_pc    <= 32'd0;
        end else if (!stall) begin
            if_id_valid <= 1'b1;
            if_id_instr <= imem_data;
            if_id_pc    <= pc;
        end
    end

    // ============================================================ ID
    logic [5:0]  opcode, func;
    logic [4:0]  rs, rt, rd, wr;
    logic        c_regwrite, c_memtoreg, c_regdst, c_alusrc, c_branch, c_jump, c_memwrite, c_memread, c_rec;
    logic [1:0]  c_aluop;
    logic [2:0]  aluoperation;
    logic [31:0] rf_rd1, rf_rd2, rd1, rd2, imm;
    logic        uses_rs, uses_rt;

    assign opcode = if_id_instr[31:26];
    assign rs     = if_id_instr[25:21];
    assign rt     = if_id_instr[20:16];
    assign rd     = if_id_instr[15:11];
    assign func   = if_id_instr[5:0];

    control_unit control_unit (
        .opcode(opcode), .RegWrite(c_regwrite), .MemToReg(c_memtoreg), .RegDst(c_regdst),
        .ALUsrc(c_alusrc), .branch(c_branch), .jump(c_jump), .memWrite(c_memwrite),
        .memRead(c_memread), .ALUop(c_aluop), .rec(c_rec)
    );
    alu_control alu_control (.ALUop(c_aluop), .func(func), .ALUoperation(aluoperation));

    register_file register_file (
        .clk(clk), .reset(reset),
        .reg_write(wb_we), .write_register(mem_wb_wr), .write_data(wb_data),
        .register_read_1(rs), .register_read_2(rt),
        .read_data_1(rf_rd1), .read_data_2(rf_rd2)
    );
    // r0 is hard-wired; a value written back this cycle is bypassed to the read
    assign rd1 = (rs == 5'd0) ? 32'd0 : (wb_we && mem_wb_wr == rs) ? wb_data : rf_rd1;
    assign rd2 = (rt == 5'd0) ? 32'd0 : (wb_we && mem_wb_wr == rt) ? wb_data : rf_rd2;

    sign_extension sign_extension (.input_16(if_id_instr[15:0]), .output_32(imm));

    assign wr      = c_regdst ? rd : rt;
    assign id_jump = if_id_valid && c_jump;
    logic [31:0] id_pc4;
    assign id_pc4  = if_id_pc + 32'd4;
    assign id_jta  = {id_pc4[31:28], if_id_instr[25:2], 2'b00};   // same JTA rule as instruction_fetch_*.sv

    // operands actually read by this instruction class
    assign uses_rs = !(c_jump || c_rec);
    assign uses_rt = (opcode == 6'b000000) || c_memwrite || c_branch;

    assign stall = if_id_valid && id_ex_valid && id_ex_memread && (id_ex_wr != 5'd0) &&
                   ((uses_rs && id_ex_wr == rs) || (uses_rt && id_ex_wr == rt));

    always_ff @(posedge clk) begin
        if (!reset || stall || ex_taken || !if_id_valid) begin   // bubble
            id_ex_valid    <= 1'b0;
            id_ex_regwrite <= 1'b0;
            id_ex_memtoreg <= 1'b0;
            id_ex_memread  <= 1'b0;
            id_ex_memwrite <= 1'b0;
            id_ex_branch   <= 1'b0;
            id_ex_rec      <= 1'b0;
            id_ex_alusrc   <= 1'b0;
            id_ex_aluop    <= 3'b000;
            id_ex_rs       <= 5'd0;
            id_ex_rt       <= 5'd0;
            id_ex_wr       <= 5'd0;
            id_ex_pc       <= 32'd0;
            id_ex_rd1      <= 32'd0;
            id_ex_rd2      <= 32'd0;
            id_ex_imm      <= 32'd0;
            id_ex_opcode   <= 6'd0;
        end else begin
            id_ex_valid    <= 1'b1;
            id_ex_regwrite <= c_regwrite;
            id_ex_memtoreg <= c_memtoreg;
            id_ex_memread  <= c_memread;
            id_ex_memwrite <= c_memwrite;
            id_ex_branch   <= c_branch;
            id_ex_rec      <= c_rec;
            id_ex_alusrc   <= c_alusrc;
            id_ex_aluop    <= aluoperation;
            id_ex_rs       <= rs;
            id_ex_rt       <= rt;
            id_ex_wr       <= wr;
            id_ex_pc       <= if_id_pc;
            id_ex_rd1      <= rd1;
            id_ex_rd2      <= rd2;
            id_ex_imm      <= imm;
            id_ex_opcode   <= opcode;
        end
    end

    // ============================================================ EX
    logic [31:0] fwd_a, fwd_b, alu_b, alu_result;
    logic        alu_zero, fwd_mem_a, fwd_mem_b, fwd_wb_a, fwd_wb_b;

    // EX/MEM can forward only ALU results; a load there has already caused a stall
    assign fwd_mem_a = ex_mem_valid && ex_mem_regwrite && !ex_mem_memread && ex_mem_wr != 5'd0 && ex_mem_wr == id_ex_rs;
    assign fwd_mem_b = ex_mem_valid && ex_mem_regwrite && !ex_mem_memread && ex_mem_wr != 5'd0 && ex_mem_wr == id_ex_rt;
    assign fwd_wb_a  = wb_we && mem_wb_wr == id_ex_rs;
    assign fwd_wb_b  = wb_we && mem_wb_wr == id_ex_rt;

    assign fwd_a = fwd_mem_a ? ex_mem_alu : fwd_wb_a ? wb_data : id_ex_rd1;
    assign fwd_b = fwd_mem_b ? ex_mem_alu : fwd_wb_b ? wb_data : id_ex_rd2;
    assign alu_b = id_ex_alusrc ? id_ex_imm : fwd_b;

    alu alu (.A(fwd_a), .B(alu_b), .ALU_operation(id_ex_aluop), .zero(alu_zero), .result(alu_result));

    assign ex_taken = id_ex_valid && id_ex_branch && alu_zero;
    assign ex_bta   = id_ex_pc + 32'd4 + (id_ex_imm << 2);

    always_ff @(posedge clk) begin
        if (!reset || !id_ex_valid) begin
            ex_mem_valid    <= 1'b0;
            ex_mem_regwrite <= 1'b0;
            ex_mem_memtoreg <= 1'b0;
            ex_mem_memread  <= 1'b0;
            ex_mem_memwrite <= 1'b0;
            ex_mem_rec      <= 1'b0;
            ex_mem_wr       <= 5'd0;
            ex_mem_pc       <= 32'd0;
            ex_mem_alu      <= 32'd0;
            ex_mem_store    <= 32'd0;
            ex_mem_opcode   <= 6'd0;
            ex_mem_aluop    <= 3'b000;
        end else begin
            ex_mem_valid    <= 1'b1;
            ex_mem_regwrite <= id_ex_regwrite;
            ex_mem_memtoreg <= id_ex_memtoreg;
            ex_mem_memread  <= id_ex_memread;
            ex_mem_memwrite <= id_ex_memwrite;
            ex_mem_rec      <= id_ex_rec;
            ex_mem_wr       <= id_ex_wr;
            ex_mem_pc       <= id_ex_pc;
            ex_mem_alu      <= alu_result;
            ex_mem_store    <= fwd_b;
            ex_mem_opcode   <= id_ex_opcode;
            ex_mem_aluop    <= id_ex_aluop;
        end
    end

    // ============================================================ MEM
    assign dmem_addr  = ex_mem_alu;
    assign dmem_wdata = ex_mem_store;
    assign dmem_read  = ex_mem_valid && ex_mem_memread;
    assign dmem_write = reset && ex_mem_valid && ex_mem_memwrite;
    assign dmem_rec   = reset && ex_mem_valid && ex_mem_rec;

    always_ff @(posedge clk) begin
        if (!reset || !ex_mem_valid) begin
            mem_wb_valid    <= 1'b0;
            mem_wb_regwrite <= 1'b0;
            mem_wb_memtoreg <= 1'b0;
            mem_wb_wr       <= 5'd0;
            mem_wb_pc       <= 32'd0;
            mem_wb_alu      <= 32'd0;
            mem_wb_mem      <= 32'd0;
            mem_wb_opcode   <= 6'd0;
            mem_wb_aluop    <= 3'b000;
        end else begin
            mem_wb_valid    <= 1'b1;
            mem_wb_regwrite <= ex_mem_regwrite;
            mem_wb_memtoreg <= ex_mem_memtoreg;
            mem_wb_wr       <= ex_mem_wr;
            mem_wb_pc       <= ex_mem_pc;
            mem_wb_alu      <= ex_mem_alu;
            mem_wb_mem      <= dmem_rdata;
            mem_wb_opcode   <= ex_mem_opcode;
            mem_wb_aluop    <= ex_mem_aluop;
        end
    end

    // ============================================================ WB / retire
    assign ret_valid  = mem_wb_valid;
    assign ret_pc     = mem_wb_pc;
    assign ret_opcode = mem_wb_opcode;
    assign ret_aluop  = mem_wb_aluop;

endmodule
