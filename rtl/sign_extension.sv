module sign_extension (
    input  logic [15:0] input_16,
    output logic [31:0] output_32
);
    assign output_32 = {{16{input_16[15]}}, input_16};

endmodule
