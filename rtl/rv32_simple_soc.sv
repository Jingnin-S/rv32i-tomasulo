`timescale 1ns/1ps

module rv32_simple_soc #(
    parameter int IMEM_WORDS = 256,
    parameter int DMEM_WORDS = 256
) (
    input  logic clk,
    input  logic rst_n,
    output logic halted,
    output logic trapped,
    output rv32_pkg::trap_cause_e trap_cause,
    output logic [31:0] committed_count,
    output logic retire_valid,
    output logic [31:0] retire_pc,
    output logic [31:0] retire_instr,
    output logic retire_rd_write,
    output logic [4:0] retire_rd,
    output logic [31:0] retire_rd_value,
    output logic retire_memory_write,
    output logic [31:0] retire_memory_address,
    output logic [31:0] retire_memory_data,
    output logic [3:0] retire_memory_strobe,
    input  logic [4:0] debug_reg_address,
    output logic [31:0] debug_reg_data
);
    import rv32_pkg::*;

    logic [31:0] imem [0:IMEM_WORDS-1];
    logic [31:0] dmem [0:DMEM_WORDS-1];

    logic imem_req_valid;
    logic imem_req_ready;
    logic [31:0] imem_req_address;
    logic imem_rsp_valid_q;
    logic imem_rsp_ready;
    logic [31:0] imem_rsp_data_q;
    logic imem_rsp_error_q;

    logic dmem_req_valid;
    logic dmem_req_ready;
    logic dmem_req_write;
    logic [31:0] dmem_req_address;
    logic [31:0] dmem_req_wdata;
    logic [3:0] dmem_req_wstrb;
    logic dmem_rsp_valid_q;
    logic dmem_rsp_ready;
    logic [31:0] dmem_rsp_rdata_q;
    logic dmem_rsp_error_q;

    assign imem_req_ready = !imem_rsp_valid_q || imem_rsp_ready;
    assign dmem_req_ready = !dmem_rsp_valid_q || dmem_rsp_ready;

    initial begin
        for (int i = 0; i < IMEM_WORDS; i++) begin
            imem[i] = '0;
        end
        for (int i = 0; i < DMEM_WORDS; i++) begin
            dmem[i] = '0;
        end
    end

    rv32_ooo_core u_core (
        .clk,
        .rst_n,
        .imem_req_valid,
        .imem_req_ready,
        .imem_req_address,
        .imem_rsp_valid(imem_rsp_valid_q),
        .imem_rsp_ready,
        .imem_rsp_data(imem_rsp_data_q),
        .imem_rsp_error(imem_rsp_error_q),
        .dmem_req_valid,
        .dmem_req_ready,
        .dmem_req_write,
        .dmem_req_address,
        .dmem_req_wdata,
        .dmem_req_wstrb,
        .dmem_rsp_valid(dmem_rsp_valid_q),
        .dmem_rsp_ready,
        .dmem_rsp_rdata(dmem_rsp_rdata_q),
        .dmem_rsp_error(dmem_rsp_error_q),
        .retire_valid,
        .retire_pc,
        .retire_instr,
        .retire_rd_write,
        .retire_rd,
        .retire_rd_value,
        .retire_memory_write,
        .retire_memory_address,
        .retire_memory_data,
        .retire_memory_strobe,
        .halted,
        .trapped,
        .trap_cause,
        .committed_count,
        .debug_reg_address,
        .debug_reg_data
    );

    always_ff @(posedge clk or negedge rst_n) begin
        int i;
        if (!rst_n) begin
            imem_rsp_valid_q <= 1'b0;
            imem_rsp_data_q <= '0;
            imem_rsp_error_q <= 1'b0;
            dmem_rsp_valid_q <= 1'b0;
            dmem_rsp_rdata_q <= '0;
            dmem_rsp_error_q <= 1'b0;
        end else begin
            if (imem_rsp_valid_q && imem_rsp_ready) begin
                imem_rsp_valid_q <= 1'b0;
            end
            if (imem_req_valid && imem_req_ready) begin
                imem_rsp_valid_q <= 1'b1;
                if ((imem_req_address >> 2) < IMEM_WORDS) begin
                    imem_rsp_data_q <= imem[imem_req_address >> 2];
                    imem_rsp_error_q <= 1'b0;
                end else begin
                    imem_rsp_data_q <= '0;
                    imem_rsp_error_q <= 1'b1;
                end
            end

            if (dmem_rsp_valid_q && dmem_rsp_ready) begin
                dmem_rsp_valid_q <= 1'b0;
            end
            if (dmem_req_valid && dmem_req_ready) begin
                if ((dmem_req_address >> 2) < DMEM_WORDS) begin
                    if (dmem_req_write) begin
                        for (i = 0; i < 4; i++) begin
                            if (dmem_req_wstrb[i]) begin
                                dmem[dmem_req_address >> 2][i*8 +: 8] <= dmem_req_wdata[i*8 +: 8];
                            end
                        end
                    end else begin
                        dmem_rsp_valid_q <= 1'b1;
                        dmem_rsp_rdata_q <= dmem[dmem_req_address >> 2];
                        dmem_rsp_error_q <= 1'b0;
                    end
                end else if (!dmem_req_write) begin
                    dmem_rsp_valid_q <= 1'b1;
                    dmem_rsp_rdata_q <= '0;
                    dmem_rsp_error_q <= 1'b1;
                end
            end
        end
    end

endmodule
