#include "rv32_model.hpp"

#include <cassert>
#include <cstdint>
#include <iostream>
#include <vector>

namespace {

using rv32::Rv32Model;

std::uint32_t enc_r(std::uint32_t funct7, std::uint32_t rs2, std::uint32_t rs1,
                    std::uint32_t funct3, std::uint32_t rd) {
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) |
           (rd << 7) | 0x33;
}

std::uint32_t enc_i(std::int32_t imm, std::uint32_t rs1, std::uint32_t funct3,
                    std::uint32_t rd, std::uint32_t opcode = 0x13) {
    return ((static_cast<std::uint32_t>(imm) & 0xfff) << 20) | (rs1 << 15) |
           (funct3 << 12) | (rd << 7) | opcode;
}

std::uint32_t enc_shift_i(std::uint32_t funct7, std::uint32_t shamt,
                          std::uint32_t rs1, std::uint32_t funct3,
                          std::uint32_t rd) {
    return (funct7 << 25) | ((shamt & 31) << 20) | (rs1 << 15) |
           (funct3 << 12) | (rd << 7) | 0x13;
}

std::uint32_t enc_s(std::int32_t imm, std::uint32_t rs2, std::uint32_t rs1,
                    std::uint32_t funct3) {
    const std::uint32_t uimm = static_cast<std::uint32_t>(imm) & 0xfff;
    return ((uimm >> 5) << 25) | (rs2 << 20) | (rs1 << 15) |
           (funct3 << 12) | ((uimm & 0x1f) << 7) | 0x23;
}

std::uint32_t enc_b(std::int32_t imm, std::uint32_t rs2, std::uint32_t rs1,
                    std::uint32_t funct3) {
    const std::uint32_t uimm = static_cast<std::uint32_t>(imm) & 0x1fff;
    return (((uimm >> 12) & 1) << 31) | (((uimm >> 5) & 0x3f) << 25) |
           (rs2 << 20) | (rs1 << 15) | (funct3 << 12) |
           (((uimm >> 1) & 0xf) << 8) | (((uimm >> 11) & 1) << 7) | 0x63;
}

std::uint32_t enc_u(std::uint32_t imm20, std::uint32_t rd,
                    std::uint32_t opcode) {
    return (imm20 << 12) | (rd << 7) | opcode;
}

std::uint32_t enc_j(std::int32_t imm, std::uint32_t rd) {
    const std::uint32_t uimm = static_cast<std::uint32_t>(imm) & 0x1fffff;
    return (((uimm >> 20) & 1) << 31) | (((uimm >> 1) & 0x3ff) << 21) |
           (((uimm >> 11) & 1) << 20) | (((uimm >> 12) & 0xff) << 12) |
           (rd << 7) | 0x6f;
}

void load_program(Rv32Model& model, const std::vector<std::uint32_t>& program) {
    for (std::size_t i = 0; i < program.size(); ++i) {
        model.load_word(static_cast<std::uint32_t>(i * 4), program[i]);
    }
}

void run_to_halt(Rv32Model& model, int limit = 256) {
    for (int i = 0; i < limit && !model.halted(); ++i) {
        const auto trace = model.step();
        assert(trace.valid);
    }
    assert(model.halted());
}

void test_integer_alu() {
    Rv32Model model;
    load_program(model, {
        enc_i(5, 0, 0, 1),
        enc_i(-2, 0, 0, 2),
        enc_r(0, 2, 1, 0, 3),       // add
        enc_r(0x20, 2, 1, 0, 4),    // sub
        enc_r(0, 1, 2, 2, 5),       // slt
        enc_r(0, 1, 2, 3, 6),       // sltu
        enc_shift_i(0, 3, 1, 1, 7), // slli
        enc_shift_i(0, 1, 7, 5, 8), // srli
        enc_shift_i(0x20, 1, 2, 5, 9), // srai
        enc_i(3, 1, 4, 10),         // xori
        enc_i(8, 1, 6, 11),         // ori
        enc_i(6, 1, 7, 12),         // andi
        enc_u(0x12345, 13, 0x37),    // lui
        enc_u(1, 14, 0x17),          // auipc
        0x00000073,
    });
    run_to_halt(model);
    const auto& x = model.registers();
    assert(x[3] == 3);
    assert(x[4] == 7);
    assert(x[5] == 1);
    assert(x[6] == 0);
    assert(x[7] == 40);
    assert(x[8] == 20);
    assert(x[9] == 0xffffffffU);
    assert(x[10] == 6);
    assert(x[11] == 13);
    assert(x[12] == 4);
    assert(x[13] == 0x12345000U);
    assert(x[14] == 0x1000U + 13U * 4U);
    assert(x[0] == 0);
    assert(model.trap_cause() == rv32::TrapCause::environment_call);
}

void test_control_flow() {
    Rv32Model model;
    load_program(model, {
        enc_i(3, 0, 0, 1),             // 0
        enc_i(0, 0, 0, 2),             // 4
        enc_i(1, 2, 0, 2),             // 8 loop
        enc_i(-1, 1, 0, 1),            // 12
        enc_b(-8, 0, 1, 1),            // 16 bne -> 8
        enc_j(8, 3),                    // 20 jal -> 28
        enc_i(99, 0, 0, 4),            // 24 skipped
        enc_u(0, 5, 0x17),             // 28 auipc
        enc_i(12, 5, 0, 6, 0x67),      // 32 jalr -> 40
        enc_i(88, 0, 0, 4),            // 36 skipped
        0x00000073,                     // 40
    });
    run_to_halt(model);
    const auto& x = model.registers();
    assert(x[1] == 0);
    assert(x[2] == 3);
    assert(x[3] == 24);
    assert(x[4] == 0);
    assert(x[5] == 28);
    assert(x[6] == 36);
}

void test_memory_widths() {
    Rv32Model model;
    load_program(model, {
        enc_i(0x100, 0, 0, 1),
        enc_i(-1, 0, 0, 2),
        enc_s(0, 2, 1, 0),              // sb
        enc_i(0, 1, 4, 3, 0x03),        // lbu
        enc_i(0, 1, 0, 4, 0x03),        // lb
        enc_s(2, 2, 1, 1),              // sh
        enc_i(2, 1, 5, 5, 0x03),        // lhu
        enc_i(2, 1, 1, 6, 0x03),        // lh
        enc_s(4, 2, 1, 2),              // sw
        enc_i(4, 1, 2, 7, 0x03),        // lw
        0x00000073,
    });
    run_to_halt(model);
    const auto& x = model.registers();
    assert(x[3] == 0xff);
    assert(x[4] == 0xffffffffU);
    assert(x[5] == 0xffff);
    assert(x[6] == 0xffffffffU);
    assert(x[7] == 0xffffffffU);
    assert(model.read_word(0x104) == 0xffffffffU);
}

void test_precise_errors() {
    {
        Rv32Model model;
        load_program(model, {enc_i(0x101, 0, 0, 1), enc_i(0, 1, 2, 2, 0x03)});
        model.step();
        const auto trace = model.step();
        assert(trace.trap);
        assert(trace.cause == rv32::TrapCause::load_address_misaligned);
        assert(model.registers()[2] == 0);
    }
    {
        Rv32Model model;
        load_program(model, {0xffffffffU});
        const auto trace = model.step();
        assert(trace.trap);
        assert(trace.cause == rv32::TrapCause::illegal_instruction);
    }
}

void test_predictor() {
    rv32::BranchPredictor predictor(4);
    constexpr std::uint32_t pc = 0x40;
    auto prediction = predictor.predict(pc);
    assert(!prediction.taken && prediction.target == pc + 4);

    predictor.update(pc, true, 0x20, rv32::BranchKind::conditional);
    prediction = predictor.predict(pc);
    assert(prediction.taken && prediction.target == 0x20);
    predictor.update(pc, false, 0x20, rv32::BranchKind::conditional);
    prediction = predictor.predict(pc);
    assert(!prediction.taken);

    predictor.update(pc, true, 0x80, rv32::BranchKind::jump);
    prediction = predictor.predict(pc);
    assert(prediction.taken && prediction.target == 0x80);

    predictor.reset();
    prediction = predictor.predict(pc);
    assert(!prediction.taken);
}

}  // namespace

int main() {
    test_integer_alu();
    test_control_flow();
    test_memory_widths();
    test_precise_errors();
    test_predictor();
    std::cout << "rv32_model tests passed\n";
    return 0;
}

