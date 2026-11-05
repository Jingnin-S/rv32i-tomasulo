`timescale 1ns/1ps

module rv32_writeback (
    input  logic                         load_valid,
    output logic                         load_ready,
    input  rv32_pkg::completion_packet_t load_completion,

    input  logic                         memory_valid,
    output logic                         memory_ready,
    input  rv32_pkg::completion_packet_t memory_completion,

    input  logic                         alu_valid,
    output logic                         alu_ready,
    input  rv32_pkg::completion_packet_t alu_completion,

    output logic                         completion_valid,
    input  logic                         completion_ready,
    output rv32_pkg::completion_packet_t completion
);
    always_comb begin
        load_ready = 1'b0;
        memory_ready = 1'b0;
        alu_ready = 1'b0;
        completion_valid = 1'b0;
        completion = '0;

        if (load_valid) begin
            completion_valid = 1'b1;
            completion = load_completion;
            load_ready = completion_ready;
        end else if (memory_valid) begin
            completion_valid = 1'b1;
            completion = memory_completion;
            memory_ready = completion_ready;
        end else if (alu_valid) begin
            completion_valid = 1'b1;
            completion = alu_completion;
            alu_ready = completion_ready;
        end
    end

endmodule

