`timescale 1ns/1ps

module tb_rv32_ooo_core;
    import rv32_pkg::*;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic halted;
    logic trapped;
    trap_cause_e trap_cause;
    logic [31:0] committed_count;
    logic retire_valid;
    logic [31:0] retire_pc;
    logic [31:0] retire_instr;
    logic retire_rd_write;
    logic [4:0] retire_rd;
    logic [31:0] retire_rd_value;
    logic retire_memory_write;
    logic [31:0] retire_memory_address;
    logic [31:0] retire_memory_data;
    logic [3:0] retire_memory_strobe;
    logic [4:0] debug_reg_address;
    logic [31:0] debug_reg_data;
    logic saw_wrong_path_retire;
    logic saw_wrong_path_store;

    rv32_simple_soc dut (
        .clk,
        .rst_n,
        .halted,
        .trapped,
        .trap_cause,
        .committed_count,
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
        .debug_reg_address,
        .debug_reg_data
    );

    always #5 clk = ~clk;

    function automatic logic [31:0] enc_r(
        input logic [6:0] funct7,
        input logic [4:0] rs2,
        input logic [4:0] rs1,
        input logic [2:0] funct3,
        input logic [4:0] rd
    );
        return {funct7, rs2, rs1, funct3, rd, 7'h33};
    endfunction

    function automatic logic [31:0] enc_i(
        input integer imm,
        input logic [4:0] rs1,
        input logic [2:0] funct3,
        input logic [4:0] rd,
        input logic [6:0] opcode
    );
        logic [11:0] value;
        value = imm[11:0];
        return {value, rs1, funct3, rd, opcode};
    endfunction

    function automatic logic [31:0] enc_shift_i(
        input logic [6:0] funct7,
        input logic [4:0] shamt,
        input logic [4:0] rs1,
        input logic [2:0] funct3,
        input logic [4:0] rd
    );
        return {funct7, shamt, rs1, funct3, rd, 7'h13};
    endfunction

    function automatic logic [31:0] enc_u(
        input logic [19:0] imm20,
        input logic [4:0] rd,
        input logic [6:0] opcode
    );
        return {imm20, rd, opcode};
    endfunction

    function automatic logic [31:0] enc_s(
        input integer imm,
        input logic [4:0] rs2,
        input logic [4:0] rs1,
        input logic [2:0] funct3
    );
        logic [11:0] value;
        value = imm[11:0];
        return {value[11:5], rs2, rs1, funct3, value[4:0], 7'h23};
    endfunction

    function automatic logic [31:0] enc_b(
        input integer imm,
        input logic [4:0] rs2,
        input logic [4:0] rs1,
        input logic [2:0] funct3
    );
        logic [12:0] value;
        value = imm[12:0];
        return {value[12], value[10:5], rs2, rs1, funct3,
                value[4:1], value[11], 7'h63};
    endfunction

    function automatic logic [31:0] enc_j(
        input integer imm,
        input logic [4:0] rd
    );
        logic [20:0] value;
        value = imm[20:0];
        return {value[20], value[10:1], value[11], value[19:12], rd, 7'h6f};
    endfunction

    task automatic expect_reg(input logic [4:0] address, input logic [31:0] expected);
        debug_reg_address = address;
        #1;
        if (debug_reg_data !== expected) begin
            $error("x%0d expected %08x, got %08x", address, expected, debug_reg_data);
        end
    endtask

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            saw_wrong_path_retire <= 1'b0;
            saw_wrong_path_store <= 1'b0;
        end else if (retire_valid) begin
            if (retire_pc == 32'd28 || retire_pc == 32'd32 || retire_pc == 32'd60 ||
                retire_pc == 32'd104) begin
                saw_wrong_path_retire <= 1'b1;
            end
            if (retire_memory_write && retire_memory_address == 32'd260 &&
                retire_memory_strobe == 4'b1111 && retire_memory_data == 32'd7) begin
                saw_wrong_path_store <= 1'b1;
            end
        end
    end

    initial begin
        int cycles;
        debug_reg_address = '0;
        saw_wrong_path_retire = 1'b0;
        saw_wrong_path_store = 1'b0;

        #1;
        for (int i = 0; i < 256; i++) begin
            dut.imem[i] = 32'h0000_0013; // addi x0,x0,0
            dut.dmem[i] = 32'd0;
        end

        dut.imem[0]  = enc_i(5,   5'd0, 3'b000, 5'd1, 7'h13);
        dut.imem[1]  = enc_i(7,   5'd0, 3'b000, 5'd2, 7'h13);
        dut.imem[2]  = enc_r(7'h00, 5'd2, 5'd1, 3'b000, 5'd3);
        dut.imem[3]  = enc_s(256, 5'd3, 5'd0, 3'b010);
        dut.imem[4]  = enc_i(256, 5'd0, 3'b010, 5'd4, 7'h03);
        dut.imem[5]  = enc_i(1,   5'd4, 3'b000, 5'd5, 7'h13);
        dut.imem[6]  = enc_b(12,  5'd5, 5'd5, 3'b000);
        dut.imem[7]  = enc_s(260, 5'd2, 5'd0, 3'b010); // wrong path
        dut.imem[8]  = 32'h0000_0073;                 // wrong-path halt
        dut.imem[9]  = enc_i(3,   5'd0, 3'b000, 5'd6, 7'h13);
        dut.imem[10] = enc_i(0,   5'd0, 3'b000, 5'd7, 7'h13);
        dut.imem[11] = enc_i(1,   5'd7, 3'b000, 5'd7, 7'h13);
        dut.imem[12] = enc_i(-1,  5'd6, 3'b000, 5'd6, 7'h13);
        dut.imem[13] = enc_b(-8,  5'd0, 5'd6, 3'b001);
        dut.imem[14] = enc_j(8, 5'd8);
        dut.imem[15] = enc_i(99, 5'd0, 3'b000, 5'd9, 7'h13); // wrong path
        dut.imem[16] = enc_i(256, 5'd0, 3'b100, 5'd10, 7'h03);
        dut.imem[17] = enc_s(261, 5'd5, 5'd0, 3'b000);
        dut.imem[18] = enc_i(261, 5'd0, 3'b100, 5'd11, 7'h03);
        dut.imem[19] = 32'h0000_0073;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;

        cycles = 0;
        while (!halted && cycles < 2000) begin
            @(posedge clk);
            cycles++;
        end

        if (!halted) begin
            for (int k = 0; k < ROB_SIZE; k++) begin
                $display("ROB[%0d] v=%0b r=%0b seq=%0d pc=%08x", k,
                         dut.u_core.u_rob.valid_q[k], dut.u_core.u_rob.ready_q[k],
                         dut.u_core.u_rob.seq_q[k], dut.u_core.u_rob.uop_q[k].pc);
                $display("RS[%0d] busy=%0b seq=%0d pc=%08x s1r=%0b s1t=%0d s1s=%0d s2r=%0b",
                         k, dut.u_core.u_int_rs.busy_q[k],
                         dut.u_core.u_int_rs.entry_q[k].seq_num,
                         dut.u_core.u_int_rs.entry_q[k].uop.pc,
                         dut.u_core.u_int_rs.entry_q[k].src1_ready,
                         dut.u_core.u_int_rs.entry_q[k].src1_tag,
                         dut.u_core.u_int_rs.entry_q[k].src1_seq,
                         dut.u_core.u_int_rs.entry_q[k].src2_ready);
            end
            $fatal(1, "timeout after %0d cycles", cycles);
        end
        if (!trapped || trap_cause != TRAP_ECALL) begin
            $error("expected ECALL trap, trapped=%0b cause=%0d", trapped, trap_cause);
        end
        if (committed_count != 32'd23) begin
            $error("expected 23 commits, got %0d", committed_count);
        end
        if (saw_wrong_path_retire) $error("wrong-path instruction retired");
        if (saw_wrong_path_store) $error("wrong-path store retired");

        expect_reg(5'd1, 32'd5);
        expect_reg(5'd2, 32'd7);
        expect_reg(5'd3, 32'd12);
        expect_reg(5'd4, 32'd12);
        expect_reg(5'd5, 32'd13);
        expect_reg(5'd6, 32'd0);
        expect_reg(5'd7, 32'd3);
        expect_reg(5'd8, 32'd60);
        expect_reg(5'd9, 32'd0);
        expect_reg(5'd10, 32'd12);
        expect_reg(5'd11, 32'd13);

        if (dut.dmem[64] !== 32'd12) $error("dmem[0x100] expected 12, got %08x", dut.dmem[64]);
        if (dut.dmem[65] !== 32'h0000_0d00) $error("dmem[0x104] expected 00000d00, got %08x", dut.dmem[65]);

        $display("rv32_ooo_core speculation test passed in %0d cycles", cycles);

        @(negedge clk);
        rst_n = 1'b0;
        repeat (3) @(posedge clk);
        for (int i = 0; i < 256; i++) begin
            dut.imem[i] = 32'h0000_0013;
            dut.dmem[i] = 32'd0;
        end

        dut.imem[0]  = enc_u(20'h12345, 5'd1, 7'h37);
        dut.imem[1]  = enc_u(20'h00001, 5'd2, 7'h17);
        dut.imem[2]  = enc_i(-8, 5'd0, 3'b000, 5'd3, 7'h13);
        dut.imem[3]  = enc_shift_i(7'h20, 5'd2, 5'd3, 3'b101, 5'd4);
        dut.imem[4]  = enc_shift_i(7'h00, 5'd2, 5'd3, 3'b101, 5'd5);
        dut.imem[5]  = enc_shift_i(7'h00, 5'd4, 5'd1, 3'b001, 5'd6);
        dut.imem[6]  = enc_i(0, 5'd3, 3'b010, 5'd7, 7'h13);
        dut.imem[7]  = enc_i(1, 5'd3, 3'b011, 5'd8, 7'h13);
        dut.imem[8]  = enc_i(255, 5'd1, 3'b111, 5'd9, 7'h13);
        dut.imem[9]  = enc_i(16'h55, 5'd9, 3'b110, 5'd9, 7'h13);
        dut.imem[10] = enc_i(-1, 5'd9, 3'b100, 5'd10, 7'h13);
        dut.imem[11] = enc_r(7'h20, 5'd7, 5'd9, 3'b000, 5'd20);
        dut.imem[12] = enc_r(7'h00, 5'd7, 5'd7, 3'b001, 5'd21);
        dut.imem[13] = enc_r(7'h00, 5'd0, 5'd3, 3'b010, 5'd22);
        dut.imem[14] = enc_r(7'h00, 5'd0, 5'd3, 3'b011, 5'd23);
        dut.imem[15] = enc_i(384, 5'd0, 3'b000, 5'd11, 7'h13);
        dut.imem[16] = enc_i(-128, 5'd0, 3'b000, 5'd12, 7'h13);
        dut.imem[17] = enc_s(0, 5'd12, 5'd11, 3'b000);
        dut.imem[18] = enc_i(0, 5'd11, 3'b000, 5'd13, 7'h03);
        dut.imem[19] = enc_i(0, 5'd11, 3'b100, 5'd14, 7'h03);
        dut.imem[20] = enc_s(2, 5'd12, 5'd11, 3'b001);
        dut.imem[21] = enc_i(2, 5'd11, 3'b001, 5'd18, 7'h03);
        dut.imem[22] = enc_i(2, 5'd11, 3'b101, 5'd19, 7'h03);
        dut.imem[23] = enc_u(20'h00000, 5'd15, 7'h17);
        dut.imem[24] = enc_i(16, 5'd15, 3'b000, 5'd15, 7'h13);
        dut.imem[25] = enc_i(0, 5'd15, 3'b000, 5'd16, 7'h67);
        dut.imem[26] = enc_i(99, 5'd0, 3'b000, 5'd17, 7'h13); // wrong path
        dut.imem[27] = 32'h0000_0073;

        @(negedge clk);
        rst_n = 1'b1;
        cycles = 0;
        while (!halted && cycles < 2000) begin
            @(posedge clk);
            cycles++;
        end

        if (!halted) $fatal(1, "RV32I ops timeout after %0d cycles", cycles);
        if (!trapped || trap_cause != TRAP_ECALL) $error("RV32I ops expected ECALL trap");
        if (committed_count != 32'd27) $error("RV32I ops expected 27 commits, got %0d", committed_count);
        if (saw_wrong_path_retire) $error("JALR wrong-path instruction retired");

        expect_reg(5'd1, 32'h1234_5000);
        expect_reg(5'd2, 32'h0000_1004);
        expect_reg(5'd3, 32'hffff_fff8);
        expect_reg(5'd4, 32'hffff_fffe);
        expect_reg(5'd5, 32'h3fff_fffe);
        expect_reg(5'd6, 32'h2345_0000);
        expect_reg(5'd7, 32'd1);
        expect_reg(5'd8, 32'd0);
        expect_reg(5'd9, 32'h0000_0055);
        expect_reg(5'd10, 32'hffff_ffaa);
        expect_reg(5'd13, 32'hffff_ff80);
        expect_reg(5'd14, 32'h0000_0080);
        expect_reg(5'd15, 32'd108);
        expect_reg(5'd16, 32'd104);
        expect_reg(5'd17, 32'd0);
        expect_reg(5'd18, 32'hffff_ff80);
        expect_reg(5'd19, 32'h0000_ff80);
        expect_reg(5'd20, 32'd84);
        expect_reg(5'd21, 32'd2);
        expect_reg(5'd22, 32'd1);
        expect_reg(5'd23, 32'd0);
        if (dut.dmem[96] !== 32'hff80_0080) $error("width test memory mismatch: %08x", dut.dmem[96]);

        $display("rv32_ooo_core RV32I ops test passed in %0d cycles", cycles);

        @(negedge clk);
        rst_n = 1'b0;
        repeat (3) @(posedge clk);
        for (int i = 0; i < 256; i++) begin
            dut.imem[i] = 32'h0000_0013;
            dut.dmem[i] = 32'd0;
        end
        dut.imem[0] = enc_i(385, 5'd0, 3'b000, 5'd1, 7'h13);
        dut.imem[1] = enc_i(0, 5'd1, 3'b010, 5'd2, 7'h03); // misaligned LW
        dut.imem[2] = enc_i(7, 5'd0, 3'b000, 5'd3, 7'h13); // younger, must not retire
        dut.imem[3] = 32'h0000_0073;

        @(negedge clk);
        rst_n = 1'b1;
        cycles = 0;
        while (!halted && cycles < 200) begin
            @(posedge clk);
            cycles++;
        end
        repeat (5) @(posedge clk);

        if (!halted || !trapped || trap_cause != TRAP_LOAD_MISALIGNED) begin
            $error("expected precise misaligned-load trap, halted=%0b trapped=%0b cause=%0d",
                   halted, trapped, trap_cause);
        end
        if (committed_count != 32'd2) $error("younger instruction retired after trap, count=%0d", committed_count);
        expect_reg(5'd1, 32'd385);
        expect_reg(5'd2, 32'd0);
        expect_reg(5'd3, 32'd0);
        $display("rv32_ooo_core precise-trap test passed in %0d cycles", cycles);
        $finish;
    end

endmodule
