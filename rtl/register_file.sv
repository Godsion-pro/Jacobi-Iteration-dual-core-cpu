module register_file (
    input  logic        clk,
    input  logic        reset,
    input  logic        reg_write,
    input  logic [4:0]  register_read_1,
    input  logic [4:0]  register_read_2,
    input  logic [4:0]  write_register,
    input  logic [31:0] write_data,
    output logic [31:0] read_data_1,
    output logic [31:0] read_data_2
);

    // 32개의 32비트 레지스터
    logic [31:0] Registers [0:16];

    // 읽기 동작
    always_comb begin
        if (!reset) begin
            read_data_1 = 32'h00000000;
            read_data_2 = 32'h00000000;
        end else begin
            read_data_1 = Registers[register_read_1];
            read_data_2 = Registers[register_read_2];
        end
    end

    // 쓰기 동작
    always_ff @(posedge clk) begin
        if (reg_write) begin
            Registers[write_register] <= write_data;
        end
    end

endmodule
