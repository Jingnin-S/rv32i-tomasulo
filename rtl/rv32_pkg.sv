`timescale 1ns/1ps

package rv32_pkg;
    localparam int XLEN = 32;
    localparam int REG_COUNT = 32;
    localparam int ROB_SIZE = 8;
    localparam int ROB_TAG_W = $clog2(ROB_SIZE);
    localparam int SEQ_W = 32;

    typedef enum logic [1:0] {
        FU_NONE,
        FU_INT,
        FU_BRANCH,
        FU_MEMORY
    } fu_kind_e;

    typedef enum logic [4:0] {
        ALU_ADD,
        ALU_SUB,
        ALU_SLL,
        ALU_SLT,
        ALU_SLTU,
        ALU_XOR,
        ALU_SRL,
        ALU_SRA,
        ALU_OR,
        ALU_AND,
        ALU_LUI,
        ALU_AUIPC
    } alu_op_e;

    typedef enum logic [3:0] {
        BR_NONE,
        BR_BEQ,
        BR_BNE,
        BR_BLT,
        BR_BGE,
        BR_BLTU,
        BR_BGEU,
        BR_JAL,
        BR_JALR
    } branch_op_e;

    typedef enum logic [1:0] {
        MEM_BYTE,
        MEM_HALF,
        MEM_WORD
    } mem_size_e;

    typedef enum logic [3:0] {
        TRAP_NONE,
        TRAP_INSTR_MISALIGNED,
        TRAP_INSTR_ACCESS,
        TRAP_ILLEGAL,
        TRAP_BREAKPOINT,
        TRAP_LOAD_MISALIGNED,
        TRAP_LOAD_ACCESS,
        TRAP_STORE_MISALIGNED,
        TRAP_STORE_ACCESS,
        TRAP_ECALL
    } trap_cause_e;

    typedef struct packed {
        logic [31:0] pc;
        logic [31:0] instr;
        logic fault;
        logic pred_taken;
        logic [31:0] pred_target;
    } fetch_packet_t;

    typedef struct packed {
        logic [31:0] pc;
        logic [31:0] instr;
        logic [4:0] rs1;
        logic [4:0] rs2;
        logic [4:0] rd;
        logic [31:0] imm;
        logic use_rs1;
        logic use_rs2;
        logic writes_rd;
        fu_kind_e fu;
        alu_op_e alu_op;
        branch_op_e branch_op;
        logic memory_write;
        mem_size_e memory_size;
        logic load_unsigned;
        logic fence;
        logic halt;
        logic illegal;
        trap_cause_e trap_cause;
        logic pred_taken;
        logic [31:0] pred_target;
    } decoded_uop_t;

    typedef struct packed {
        decoded_uop_t uop;
        logic [ROB_TAG_W-1:0] rob_tag;
        logic [SEQ_W-1:0] seq_num;
        logic src1_ready;
        logic [31:0] src1_value;
        logic [ROB_TAG_W-1:0] src1_tag;
        logic [SEQ_W-1:0] src1_seq;
        logic src2_ready;
        logic [31:0] src2_value;
        logic [ROB_TAG_W-1:0] src2_tag;
        logic [SEQ_W-1:0] src2_seq;
    } dispatch_packet_t;

    typedef struct packed {
        logic [ROB_TAG_W-1:0] rob_tag;
        logic [SEQ_W-1:0] seq_num;
        logic [31:0] value;
        logic exception;
        trap_cause_e trap_cause;
        logic is_control;
        logic actual_taken;
        logic [31:0] actual_target;
        logic mispredict;
        logic is_store;
        logic [31:0] store_address;
        logic [31:0] store_data;
        logic [3:0] store_strobe;
    } completion_packet_t;

    typedef struct packed {
        logic [ROB_TAG_W-1:0] rob_tag;
        logic [SEQ_W-1:0] seq_num;
        logic [31:0] pc;
        logic [31:0] instr;
        logic writes_rd;
        logic [4:0] rd;
        logic [31:0] value;
        logic is_store;
        logic [31:0] store_address;
        logic [31:0] store_data;
        logic [3:0] store_strobe;
        logic is_control;
        logic actual_taken;
        logic [31:0] actual_target;
        branch_op_e branch_op;
        logic halt;
        logic exception;
        trap_cause_e trap_cause;
    } commit_packet_t;

    typedef struct packed {
        logic [ROB_TAG_W-1:0] rob_tag;
        logic [SEQ_W-1:0] seq_num;
        logic [31:0] address;
        logic [31:0] store_data;
        mem_size_e size;
        logic load_unsigned;
    } load_request_t;

endpackage
