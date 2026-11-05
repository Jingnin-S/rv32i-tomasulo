`timescale 1ns/1ps

module rv32_lsq #(
    parameter int ENTRY_COUNT = 8
) (
    input  logic clk,
    input  logic rst_n,

    output logic                       dispatch_ready,
    input  logic                       dispatch_fire,
    input  rv32_pkg::dispatch_packet_t dispatch,

    input  logic                         completion_valid,
    input  rv32_pkg::completion_packet_t completion,

    output logic                       load_valid,
    input  logic                       load_ready,
    output rv32_pkg::load_request_t    load_request,

    output logic                         result_valid,
    input  logic                         result_ready,
    output rv32_pkg::completion_packet_t result,

    input  logic                         store_commit_fire,
    input  logic [rv32_pkg::ROB_TAG_W-1:0] store_commit_tag,

    input  logic                       recover_valid,
    input  logic [rv32_pkg::SEQ_W-1:0] recover_seq
);
    import rv32_pkg::*;

    localparam int IDX_W = $clog2(ENTRY_COUNT);
    logic busy_q [0:ENTRY_COUNT-1];
    logic result_sent_q [0:ENTRY_COUNT-1];
    dispatch_packet_t entry_q [0:ENTRY_COUNT-1];

    logic found_free;
    logic [IDX_W-1:0] free_idx;
    logic found_load;
    logic [IDX_W-1:0] load_idx;
    logic found_result;
    logic [IDX_W-1:0] result_idx;
    logic result_is_load;

    function automatic logic misaligned(input dispatch_packet_t packet);
        logic [31:0] address;
        begin
            address = packet.src1_value + packet.uop.imm;
            unique case (packet.uop.memory_size)
                MEM_BYTE: misaligned = 1'b0;
                MEM_HALF: misaligned = address[0];
                default:  misaligned = |address[1:0];
            endcase
        end
    endfunction

    always_comb begin
        logic older_store;
        logic [31:0] address;
        logic [1:0] byte_offset;

        found_free = 1'b0;
        free_idx = '0;
        found_load = 1'b0;
        load_idx = '0;
        load_request = '0;
        found_result = 1'b0;
        result_idx = '0;
        result_is_load = 1'b0;
        result = '0;

        for (int i = 0; i < ENTRY_COUNT; i++) begin
            if (!found_free && !busy_q[i]) begin
                found_free = 1'b1;
                free_idx = i[IDX_W-1:0];
            end

            if (busy_q[i] && entry_q[i].src1_ready && entry_q[i].src2_ready &&
                !result_sent_q[i]) begin
                if (misaligned(entry_q[i])) begin
                    if (!found_result || entry_q[i].seq_num < result.seq_num) begin
                        found_result = 1'b1;
                        result_idx = i[IDX_W-1:0];
                        result_is_load = !entry_q[i].uop.memory_write;
                        result = '0;
                        result.rob_tag = entry_q[i].rob_tag;
                        result.seq_num = entry_q[i].seq_num;
                        result.exception = 1'b1;
                        result.trap_cause = entry_q[i].uop.memory_write ?
                                            TRAP_STORE_MISALIGNED : TRAP_LOAD_MISALIGNED;
                        result.is_store = entry_q[i].uop.memory_write;
                    end
                end else if (entry_q[i].uop.memory_write) begin
                    if (!found_result || entry_q[i].seq_num < result.seq_num) begin
                        address = entry_q[i].src1_value + entry_q[i].uop.imm;
                        byte_offset = address[1:0];
                        found_result = 1'b1;
                        result_idx = i[IDX_W-1:0];
                        result_is_load = 1'b0;
                        result = '0;
                        result.rob_tag = entry_q[i].rob_tag;
                        result.seq_num = entry_q[i].seq_num;
                        result.is_store = 1'b1;
                        result.store_address = {address[31:2], 2'b00};
                        unique case (entry_q[i].uop.memory_size)
                            MEM_BYTE: begin
                                result.store_strobe = 4'b0001 << byte_offset;
                                result.store_data = entry_q[i].src2_value << (byte_offset * 8);
                            end
                            MEM_HALF: begin
                                result.store_strobe = 4'b0011 << byte_offset;
                                result.store_data = entry_q[i].src2_value << (byte_offset * 8);
                            end
                            default: begin
                                result.store_strobe = 4'b1111;
                                result.store_data = entry_q[i].src2_value;
                            end
                        endcase
                    end
                end
            end
        end

        for (int i = 0; i < ENTRY_COUNT; i++) begin
            older_store = 1'b0;
            if (busy_q[i] && !entry_q[i].uop.memory_write &&
                entry_q[i].src1_ready && entry_q[i].src2_ready &&
                !misaligned(entry_q[i])) begin
                for (int j = 0; j < ENTRY_COUNT; j++) begin
                    if (busy_q[j] && entry_q[j].uop.memory_write &&
                        entry_q[j].seq_num < entry_q[i].seq_num) begin
                        older_store = 1'b1;
                    end
                end
                if (!older_store && (!found_load || entry_q[i].seq_num < load_request.seq_num)) begin
                    found_load = 1'b1;
                    load_idx = i[IDX_W-1:0];
                    load_request.rob_tag = entry_q[i].rob_tag;
                    load_request.seq_num = entry_q[i].seq_num;
                    load_request.address = entry_q[i].src1_value + entry_q[i].uop.imm;
                    load_request.store_data = '0;
                    load_request.size = entry_q[i].uop.memory_size;
                    load_request.load_unsigned = entry_q[i].uop.load_unsigned;
                end
            end
        end

        dispatch_ready = found_free;
        load_valid = found_load;
        result_valid = found_result;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        int i;

        if (!rst_n) begin
            for (i = 0; i < ENTRY_COUNT; i++) begin
                busy_q[i] <= 1'b0;
                result_sent_q[i] <= 1'b0;
                entry_q[i] <= '0;
            end
        end else if (recover_valid) begin
            for (i = 0; i < ENTRY_COUNT; i++) begin
                if (busy_q[i] && entry_q[i].seq_num > recover_seq) begin
                    busy_q[i] <= 1'b0;
                    result_sent_q[i] <= 1'b0;
                end
            end
        end else begin
            if (completion_valid) begin
                for (i = 0; i < ENTRY_COUNT; i++) begin
                    if (busy_q[i]) begin
                        if (!entry_q[i].src1_ready && entry_q[i].src1_tag == completion.rob_tag &&
                            entry_q[i].src1_seq == completion.seq_num) begin
                            entry_q[i].src1_ready <= 1'b1;
                            entry_q[i].src1_value <= completion.value;
                        end
                        if (!entry_q[i].src2_ready && entry_q[i].src2_tag == completion.rob_tag &&
                            entry_q[i].src2_seq == completion.seq_num) begin
                            entry_q[i].src2_ready <= 1'b1;
                            entry_q[i].src2_value <= completion.value;
                        end
                    end
                end
            end
            if (dispatch_fire) begin
                busy_q[free_idx] <= 1'b1;
                result_sent_q[free_idx] <= 1'b0;
                entry_q[free_idx] <= dispatch;
            end
            if (load_valid && load_ready) begin
                busy_q[load_idx] <= 1'b0;
                result_sent_q[load_idx] <= 1'b0;
            end
            if (result_valid && result_ready) begin
                if (result_is_load) begin
                    busy_q[result_idx] <= 1'b0;
                end else begin
                    result_sent_q[result_idx] <= 1'b1;
                end
            end
            if (store_commit_fire) begin
                for (i = 0; i < ENTRY_COUNT; i++) begin
                    if (busy_q[i] && entry_q[i].rob_tag == store_commit_tag) begin
                        busy_q[i] <= 1'b0;
                        result_sent_q[i] <= 1'b0;
                    end
                end
            end
        end
    end

endmodule
