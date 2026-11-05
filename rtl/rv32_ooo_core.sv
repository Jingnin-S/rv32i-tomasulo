`timescale 1ns/1ps

module rv32_ooo_core (
    input  logic clk,
    input  logic rst_n,

    output logic        imem_req_valid,
    input  logic        imem_req_ready,
    output logic [31:0] imem_req_address,
    input  logic        imem_rsp_valid,
    output logic        imem_rsp_ready,
    input  logic [31:0] imem_rsp_data,
    input  logic        imem_rsp_error,

    output logic        dmem_req_valid,
    input  logic        dmem_req_ready,
    output logic        dmem_req_write,
    output logic [31:0] dmem_req_address,
    output logic [31:0] dmem_req_wdata,
    output logic [3:0]  dmem_req_wstrb,
    input  logic        dmem_rsp_valid,
    output logic        dmem_rsp_ready,
    input  logic [31:0] dmem_rsp_rdata,
    input  logic        dmem_rsp_error,

    output logic        retire_valid,
    output logic [31:0] retire_pc,
    output logic [31:0] retire_instr,
    output logic        retire_rd_write,
    output logic [4:0]  retire_rd,
    output logic [31:0] retire_rd_value,
    output logic        retire_memory_write,
    output logic [31:0] retire_memory_address,
    output logic [31:0] retire_memory_data,
    output logic [3:0]  retire_memory_strobe,

    output logic        halted,
    output logic        trapped,
    output rv32_pkg::trap_cause_e trap_cause,
    output logic [31:0] committed_count,

    input  logic [4:0]  debug_reg_address,
    output logic [31:0] debug_reg_data
);
    import rv32_pkg::*;

    logic fetch_valid;
    logic fetch_ready;
    fetch_packet_t fetch_packet;
    logic uop_valid;
    logic uop_ready;
    decoded_uop_t decoded_uop;

    logic rob_alloc_ready;
    logic [ROB_TAG_W-1:0] rob_alloc_tag;
    logic [SEQ_W-1:0] rob_alloc_seq;
    logic [$clog2(ROB_SIZE+1)-1:0] rob_occupancy;

    logic query1_valid;
    logic [ROB_TAG_W-1:0] query1_tag;
    logic query1_ready;
    logic [31:0] query1_value;
    logic [SEQ_W-1:0] query1_seq;
    logic query2_valid;
    logic [ROB_TAG_W-1:0] query2_tag;
    logic query2_ready;
    logic [31:0] query2_value;
    logic [SEQ_W-1:0] query2_seq;
    logic src1_ready;
    logic [31:0] src1_value;
    logic [ROB_TAG_W-1:0] src1_tag;
    logic [SEQ_W-1:0] src1_seq;
    logic src2_ready;
    logic [31:0] src2_value;
    logic [ROB_TAG_W-1:0] src2_tag;
    logic [SEQ_W-1:0] src2_seq;

    logic dispatch_fire;
    logic rs_dispatch_ready;
    logic rs_dispatch_fire;
    logic lsq_dispatch_ready;
    logic lsq_dispatch_fire;
    dispatch_packet_t dispatch_packet;

    logic rs_issue_valid;
    logic rs_issue_ready;
    dispatch_packet_t rs_issue;

    logic alu_completion_valid;
    logic alu_completion_ready;
    completion_packet_t alu_completion;
    logic memory_result_valid;
    logic memory_result_ready;
    completion_packet_t memory_result;
    logic load_completion_valid;
    logic load_completion_ready;
    completion_packet_t load_completion;
    logic wb_valid;
    completion_packet_t wb_completion;

    logic load_request_valid;
    logic load_request_ready;
    load_request_t load_request;

    logic rob_commit_valid;
    logic rob_commit_ready;
    logic rob_commit_fire;
    commit_packet_t rob_commit;

    logic recover_valid;
    logic [31:0] recover_pc;

    logic lsu_store_valid;
    logic lsu_store_ready;

    assign recover_valid = wb_valid && wb_completion.is_control && wb_completion.mispredict;
    assign recover_pc = wb_completion.actual_target;

    rv32_frontend u_frontend (
        .clk,
        .rst_n,
        .imem_req_valid,
        .imem_req_ready,
        .imem_req_address,
        .imem_rsp_valid,
        .imem_rsp_ready,
        .imem_rsp_data,
        .imem_rsp_error,
        .fetch_valid,
        .fetch_ready,
        .fetch_packet,
        .redirect_valid(recover_valid),
        .redirect_pc(recover_pc),
        .predictor_update_valid(rob_commit_fire && rob_commit.is_control && !rob_commit.exception),
        .predictor_update_pc(rob_commit.pc),
        .predictor_update_taken(rob_commit.actual_taken),
        .predictor_update_target(rob_commit.actual_target),
        .predictor_update_op(rob_commit.branch_op)
    );

    rv32_decode u_decode (
        .fetch_valid,
        .fetch_ready,
        .fetch_packet,
        .uop_valid,
        .uop_ready,
        .uop(decoded_uop)
    );

    rv32_rename u_rename (
        .clk,
        .rst_n,
        .lookup_uop(decoded_uop),
        .query1_valid,
        .query1_tag,
        .query1_ready,
        .query1_value,
        .query1_seq,
        .query2_valid,
        .query2_tag,
        .query2_ready,
        .query2_value,
        .query2_seq,
        .completion_valid(wb_valid),
        .completion(wb_completion),
        .src1_ready,
        .src1_value,
        .src1_tag,
        .src1_seq,
        .src2_ready,
        .src2_value,
        .src2_tag,
        .src2_seq,
        .dispatch_fire,
        .dispatch_tag(rob_alloc_tag),
        .dispatch_seq(rob_alloc_seq),
        .dispatch_uop(decoded_uop),
        .commit_fire(rob_commit_fire),
        .commit(rob_commit),
        .recover_valid,
        .recover_tag(wb_completion.rob_tag),
        .recover_seq(wb_completion.seq_num),
        .debug_reg_address,
        .debug_reg_data
    );

    rv32_rob u_rob (
        .clk,
        .rst_n,
        .alloc_ready(rob_alloc_ready),
        .alloc_tag(rob_alloc_tag),
        .alloc_seq(rob_alloc_seq),
        .dispatch_fire,
        .dispatch_uop(decoded_uop),
        .query1_valid,
        .query1_tag,
        .query1_ready,
        .query1_value,
        .query1_seq,
        .query2_valid,
        .query2_tag,
        .query2_ready,
        .query2_value,
        .query2_seq,
        .completion_valid(wb_valid),
        .completion(wb_completion),
        .commit_valid(rob_commit_valid),
        .commit_ready(rob_commit_ready),
        .commit(rob_commit),
        .commit_fire(rob_commit_fire),
        .recover_valid,
        .recover_tag(wb_completion.rob_tag),
        .recover_seq(wb_completion.seq_num),
        .occupancy(rob_occupancy)
    );

    rv32_int_rs u_int_rs (
        .clk,
        .rst_n,
        .dispatch_ready(rs_dispatch_ready),
        .dispatch_fire(rs_dispatch_fire),
        .dispatch(dispatch_packet),
        .completion_valid(wb_valid),
        .completion(wb_completion),
        .issue_valid(rs_issue_valid),
        .issue_ready(rs_issue_ready),
        .issue(rs_issue),
        .recover_valid,
        .recover_seq(wb_completion.seq_num)
    );

    rv32_alu_branch u_alu_branch (
        .clk,
        .rst_n,
        .issue_valid(rs_issue_valid),
        .issue_ready(rs_issue_ready),
        .issue(rs_issue),
        .completion_valid(alu_completion_valid),
        .completion_ready(alu_completion_ready),
        .completion(alu_completion),
        .recover_valid,
        .recover_seq(wb_completion.seq_num)
    );

    rv32_lsq u_lsq (
        .clk,
        .rst_n,
        .dispatch_ready(lsq_dispatch_ready),
        .dispatch_fire(lsq_dispatch_fire),
        .dispatch(dispatch_packet),
        .completion_valid(wb_valid),
        .completion(wb_completion),
        .load_valid(load_request_valid),
        .load_ready(load_request_ready),
        .load_request,
        .result_valid(memory_result_valid),
        .result_ready(memory_result_ready),
        .result(memory_result),
        .store_commit_fire(rob_commit_fire && rob_commit.is_store),
        .store_commit_tag(rob_commit.rob_tag),
        .recover_valid,
        .recover_seq(wb_completion.seq_num)
    );

    rv32_lsu u_lsu (
        .clk,
        .rst_n,
        .load_valid(load_request_valid),
        .load_ready(load_request_ready),
        .load_request,
        .store_valid(lsu_store_valid),
        .store_ready(lsu_store_ready),
        .store_commit(rob_commit),
        .dmem_req_valid,
        .dmem_req_ready,
        .dmem_req_write,
        .dmem_req_address,
        .dmem_req_wdata,
        .dmem_req_wstrb,
        .dmem_rsp_valid,
        .dmem_rsp_ready,
        .dmem_rsp_rdata,
        .dmem_rsp_error,
        .completion_valid(load_completion_valid),
        .completion_ready(load_completion_ready),
        .completion(load_completion),
        .recover_valid,
        .recover_seq(wb_completion.seq_num)
    );

    rv32_writeback u_writeback (
        .load_valid(load_completion_valid),
        .load_ready(load_completion_ready),
        .load_completion,
        .memory_valid(memory_result_valid),
        .memory_ready(memory_result_ready),
        .memory_completion(memory_result),
        .alu_valid(alu_completion_valid),
        .alu_ready(alu_completion_ready),
        .alu_completion,
        .completion_valid(wb_valid),
        .completion_ready(1'b1),
        .completion(wb_completion)
    );

    always_comb begin
        dispatch_packet = '0;
        dispatch_packet.uop = decoded_uop;
        dispatch_packet.rob_tag = rob_alloc_tag;
        dispatch_packet.seq_num = rob_alloc_seq;
        dispatch_packet.src1_ready = src1_ready;
        dispatch_packet.src1_value = src1_value;
        dispatch_packet.src1_tag = src1_tag;
        dispatch_packet.src1_seq = src1_seq;
        dispatch_packet.src2_ready = src2_ready;
        dispatch_packet.src2_value = src2_value;
        dispatch_packet.src2_tag = src2_tag;
        dispatch_packet.src2_seq = src2_seq;

        uop_ready = !halted && !recover_valid && rob_alloc_ready &&
                    ((decoded_uop.fu == FU_INT || decoded_uop.fu == FU_BRANCH) ?
                        rs_dispatch_ready :
                     (decoded_uop.fu == FU_MEMORY) ? lsq_dispatch_ready : 1'b1);
        dispatch_fire = uop_valid && uop_ready;
        rs_dispatch_fire = dispatch_fire &&
                           (decoded_uop.fu == FU_INT || decoded_uop.fu == FU_BRANCH);
        lsq_dispatch_fire = dispatch_fire && decoded_uop.fu == FU_MEMORY;

        lsu_store_valid = !halted && rob_commit_valid && rob_commit.is_store && !rob_commit.exception;
        rob_commit_ready = !halted &&
                           (rob_commit.is_store && !rob_commit.exception ? lsu_store_ready : 1'b1);

        retire_valid = rob_commit_fire;
        retire_pc = rob_commit.pc;
        retire_instr = rob_commit.instr;
        retire_rd_write = rob_commit_fire && rob_commit.writes_rd && !rob_commit.exception;
        retire_rd = rob_commit.rd;
        retire_rd_value = rob_commit.value;
        retire_memory_write = rob_commit_fire && rob_commit.is_store && !rob_commit.exception;
        retire_memory_address = rob_commit.store_address;
        retire_memory_data = rob_commit.store_data;
        retire_memory_strobe = rob_commit.store_strobe;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            halted <= 1'b0;
            trapped <= 1'b0;
            trap_cause <= TRAP_NONE;
            committed_count <= '0;
        end else if (rob_commit_fire) begin
            committed_count <= committed_count + 1'b1;
            if (rob_commit.halt || rob_commit.exception) begin
                halted <= 1'b1;
                trapped <= rob_commit.exception;
                trap_cause <= rob_commit.trap_cause;
            end
        end
    end

    logic _unused;
    always_comb _unused = ^rob_occupancy;

endmodule
