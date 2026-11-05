`timescale 1ns/1ps

module rv32_rename (
    input  logic clk,
    input  logic rst_n,

    input  rv32_pkg::decoded_uop_t lookup_uop,
    output logic                    query1_valid,
    output logic [rv32_pkg::ROB_TAG_W-1:0] query1_tag,
    input  logic                    query1_ready,
    input  logic [31:0]             query1_value,
    input  logic [rv32_pkg::SEQ_W-1:0] query1_seq,
    output logic                    query2_valid,
    output logic [rv32_pkg::ROB_TAG_W-1:0] query2_tag,
    input  logic                    query2_ready,
    input  logic [31:0]             query2_value,
    input  logic [rv32_pkg::SEQ_W-1:0] query2_seq,

    input  logic                         completion_valid,
    input  rv32_pkg::completion_packet_t completion,

    output logic                    src1_ready,
    output logic [31:0]             src1_value,
    output logic [rv32_pkg::ROB_TAG_W-1:0] src1_tag,
    output logic [rv32_pkg::SEQ_W-1:0] src1_seq,
    output logic                    src2_ready,
    output logic [31:0]             src2_value,
    output logic [rv32_pkg::ROB_TAG_W-1:0] src2_tag,
    output logic [rv32_pkg::SEQ_W-1:0] src2_seq,

    input  logic                         dispatch_fire,
    input  logic [rv32_pkg::ROB_TAG_W-1:0] dispatch_tag,
    input  logic [rv32_pkg::SEQ_W-1:0]    dispatch_seq,
    input  rv32_pkg::decoded_uop_t        dispatch_uop,

    input  logic                       commit_fire,
    input  rv32_pkg::commit_packet_t   commit,

    input  logic                         recover_valid,
    input  logic [rv32_pkg::ROB_TAG_W-1:0] recover_tag,
    input  logic [rv32_pkg::SEQ_W-1:0]    recover_seq,

    input  logic [4:0] debug_reg_address,
    output logic [31:0] debug_reg_data
);
    import rv32_pkg::*;

    logic [31:0] regfile [0:REG_COUNT-1];
    logic rat_valid [0:REG_COUNT-1];
    logic [ROB_TAG_W-1:0] rat_tag [0:REG_COUNT-1];
    logic [SEQ_W-1:0] rat_seq [0:REG_COUNT-1];

    logic checkpoint_active [0:ROB_SIZE-1];
    logic [SEQ_W-1:0] checkpoint_seq [0:ROB_SIZE-1];
    logic checkpoint_valid [0:ROB_SIZE-1][0:REG_COUNT-1];
    logic [ROB_TAG_W-1:0] checkpoint_tag [0:ROB_SIZE-1][0:REG_COUNT-1];
    logic [SEQ_W-1:0] checkpoint_rat_seq [0:ROB_SIZE-1][0:REG_COUNT-1];

    always_comb begin
        debug_reg_data = debug_reg_address == 5'd0 ? 32'd0 : regfile[debug_reg_address];
        query1_valid = lookup_uop.use_rs1 && rat_valid[lookup_uop.rs1];
        query1_tag = rat_tag[lookup_uop.rs1];
        query2_valid = lookup_uop.use_rs2 && rat_valid[lookup_uop.rs2];
        query2_tag = rat_tag[lookup_uop.rs2];
    end

    always_comb begin
        src1_ready = 1'b1;
        src1_value = 32'd0;
        src1_tag = query1_tag;
        src1_seq = rat_seq[lookup_uop.rs1];
        if (lookup_uop.use_rs1) begin
            if (!rat_valid[lookup_uop.rs1]) begin
                src1_value = regfile[lookup_uop.rs1];
            end else if (completion_valid && completion.rob_tag == query1_tag &&
                         completion.seq_num == src1_seq) begin
                src1_value = completion.value;
            end else if (query1_ready && query1_seq == src1_seq) begin
                src1_value = query1_value;
            end else begin
                src1_ready = 1'b0;
            end
        end

        src2_ready = 1'b1;
        src2_value = 32'd0;
        src2_tag = query2_tag;
        src2_seq = rat_seq[lookup_uop.rs2];
        if (lookup_uop.use_rs2) begin
            if (!rat_valid[lookup_uop.rs2]) begin
                src2_value = regfile[lookup_uop.rs2];
            end else if (completion_valid && completion.rob_tag == query2_tag &&
                         completion.seq_num == src2_seq) begin
                src2_value = completion.value;
            end else if (query2_ready && query2_seq == src2_seq) begin
                src2_value = query2_value;
            end else begin
                src2_ready = 1'b0;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        int i;
        int j;
        logic is_control;

        if (!rst_n) begin
            for (i = 0; i < REG_COUNT; i++) begin
                regfile[i] <= '0;
                rat_valid[i] <= 1'b0;
                rat_tag[i] <= '0;
                rat_seq[i] <= '0;
            end
            for (i = 0; i < ROB_SIZE; i++) begin
                checkpoint_active[i] <= 1'b0;
                checkpoint_seq[i] <= '0;
                for (j = 0; j < REG_COUNT; j++) begin
                    checkpoint_valid[i][j] <= 1'b0;
                    checkpoint_tag[i][j] <= '0;
                    checkpoint_rat_seq[i][j] <= '0;
                end
            end
        end else if (recover_valid) begin
            for (i = 0; i < REG_COUNT; i++) begin
                rat_valid[i] <= checkpoint_valid[recover_tag][i];
                rat_tag[i] <= checkpoint_tag[recover_tag][i];
                rat_seq[i] <= checkpoint_rat_seq[recover_tag][i];
            end
            for (i = 0; i < ROB_SIZE; i++) begin
                if (checkpoint_active[i] && checkpoint_seq[i] >= recover_seq) begin
                    checkpoint_active[i] <= 1'b0;
                end
            end
        end else begin
            if (commit_fire) begin
                if (commit.writes_rd && !commit.exception && commit.rd != 5'd0) begin
                    regfile[commit.rd] <= commit.value;
                    if (rat_valid[commit.rd] && rat_tag[commit.rd] == commit.rob_tag &&
                        rat_seq[commit.rd] == commit.seq_num) begin
                        rat_valid[commit.rd] <= 1'b0;
                    end
                    for (i = 0; i < ROB_SIZE; i++) begin
                        if (checkpoint_active[i] && checkpoint_valid[i][commit.rd] &&
                            checkpoint_tag[i][commit.rd] == commit.rob_tag &&
                            checkpoint_rat_seq[i][commit.rd] == commit.seq_num) begin
                            checkpoint_valid[i][commit.rd] <= 1'b0;
                        end
                    end
                end
                if (commit.is_control) begin
                    checkpoint_active[commit.rob_tag] <= 1'b0;
                end
            end

            if (dispatch_fire) begin
                is_control = dispatch_uop.branch_op != BR_NONE;
                if (is_control) begin
                    checkpoint_active[dispatch_tag] <= 1'b1;
                    checkpoint_seq[dispatch_tag] <= dispatch_seq;
                    for (i = 0; i < REG_COUNT; i++) begin
                        if (commit_fire && commit.writes_rd && !commit.exception &&
                            commit.rd == i[4:0] && rat_valid[i] &&
                            rat_tag[i] == commit.rob_tag && rat_seq[i] == commit.seq_num) begin
                            checkpoint_valid[dispatch_tag][i] <= 1'b0;
                        end else begin
                            checkpoint_valid[dispatch_tag][i] <= rat_valid[i];
                        end
                        checkpoint_tag[dispatch_tag][i] <= rat_tag[i];
                        checkpoint_rat_seq[dispatch_tag][i] <= rat_seq[i];
                    end
                    if (dispatch_uop.writes_rd && dispatch_uop.rd != 5'd0) begin
                        checkpoint_valid[dispatch_tag][dispatch_uop.rd] <= 1'b1;
                        checkpoint_tag[dispatch_tag][dispatch_uop.rd] <= dispatch_tag;
                        checkpoint_rat_seq[dispatch_tag][dispatch_uop.rd] <= dispatch_seq;
                    end
                end
                if (dispatch_uop.writes_rd && dispatch_uop.rd != 5'd0) begin
                    rat_valid[dispatch_uop.rd] <= 1'b1;
                    rat_tag[dispatch_uop.rd] <= dispatch_tag;
                    rat_seq[dispatch_uop.rd] <= dispatch_seq;
                end
            end

            regfile[0] <= 32'd0;
            rat_valid[0] <= 1'b0;
        end
    end

endmodule
