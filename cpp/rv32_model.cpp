#include "rv32_model.hpp"

#include <algorithm>
#include <stdexcept>

namespace rv32 {
namespace {

std::uint32_t sign_extend(std::uint32_t value, unsigned bits) {
    const std::uint32_t sign = std::uint32_t{1} << (bits - 1);
    return (value ^ sign) - sign;
}

std::int32_t as_signed(std::uint32_t value) {
    return static_cast<std::int32_t>(value);
}

}  // namespace

Rv32Model::Rv32Model(std::size_t memory_bytes) : memory_(memory_bytes, 0) {
    if (memory_bytes < 4) {
        throw std::invalid_argument("RV32 memory must contain at least one word");
    }
    reset();
}

void Rv32Model::reset(std::uint32_t reset_pc) {
    registers_.fill(0);
    pc_ = reset_pc;
    halted_ = false;
    trapped_ = false;
    trap_cause_ = TrapCause::none;
}

bool Rv32Model::range_ok(std::uint32_t address, std::size_t bytes) const {
    return address <= memory_.size() && bytes <= memory_.size() - address;
}

std::uint16_t Rv32Model::read_u16(std::uint32_t address) const {
    return static_cast<std::uint16_t>(memory_[address]) |
           (static_cast<std::uint16_t>(memory_[address + 1]) << 8);
}

std::uint32_t Rv32Model::read_u32(std::uint32_t address) const {
    return static_cast<std::uint32_t>(memory_[address]) |
           (static_cast<std::uint32_t>(memory_[address + 1]) << 8) |
           (static_cast<std::uint32_t>(memory_[address + 2]) << 16) |
           (static_cast<std::uint32_t>(memory_[address + 3]) << 24);
}

void Rv32Model::write_u8(std::uint32_t address, std::uint8_t value) {
    memory_[address] = value;
}

void Rv32Model::write_u16(std::uint32_t address, std::uint16_t value) {
    memory_[address] = static_cast<std::uint8_t>(value);
    memory_[address + 1] = static_cast<std::uint8_t>(value >> 8);
}

void Rv32Model::write_u32(std::uint32_t address, std::uint32_t value) {
    memory_[address] = static_cast<std::uint8_t>(value);
    memory_[address + 1] = static_cast<std::uint8_t>(value >> 8);
    memory_[address + 2] = static_cast<std::uint8_t>(value >> 16);
    memory_[address + 3] = static_cast<std::uint8_t>(value >> 24);
}

void Rv32Model::load_word(std::uint32_t address, std::uint32_t value) {
    if ((address & 3U) != 0 || !range_ok(address, 4)) {
        throw std::out_of_range("unaligned or out-of-range model word load");
    }
    write_u32(address, value);
}

std::uint32_t Rv32Model::read_word(std::uint32_t address) const {
    if ((address & 3U) != 0 || !range_ok(address, 4)) {
        throw std::out_of_range("unaligned or out-of-range model word read");
    }
    return read_u32(address);
}

RetireTrace Rv32Model::raise_trap(std::uint32_t instruction, TrapCause cause) {
    RetireTrace trace;
    trace.valid = true;
    trace.pc = pc_;
    trace.instruction = instruction;
    trace.trap = true;
    trace.cause = cause;
    halted_ = true;
    trapped_ = true;
    trap_cause_ = cause;
    registers_[0] = 0;
    return trace;
}

RetireTrace Rv32Model::step() {
    if (halted_) {
        return {};
    }
    if ((pc_ & 3U) != 0) {
        return raise_trap(0, TrapCause::instruction_address_misaligned);
    }
    if (!range_ok(pc_, 4)) {
        return raise_trap(0, TrapCause::instruction_access_fault);
    }

    const std::uint32_t instruction = read_u32(pc_);
    const std::uint32_t opcode = instruction & 0x7fU;
    const std::uint32_t rd = (instruction >> 7) & 0x1fU;
    const std::uint32_t funct3 = (instruction >> 12) & 7U;
    const std::uint32_t rs1 = (instruction >> 15) & 0x1fU;
    const std::uint32_t rs2 = (instruction >> 20) & 0x1fU;
    const std::uint32_t funct7 = instruction >> 25;
    const std::uint32_t lhs = registers_[rs1];
    const std::uint32_t rhs = registers_[rs2];
    const std::uint32_t imm_i = sign_extend(instruction >> 20, 12);
    const std::uint32_t imm_s = sign_extend(((instruction >> 25) << 5) |
                                                ((instruction >> 7) & 0x1fU),
                                            12);
    const std::uint32_t imm_b = sign_extend(((instruction >> 31) << 12) |
                                                (((instruction >> 7) & 1U) << 11) |
                                                (((instruction >> 25) & 0x3fU) << 5) |
                                                (((instruction >> 8) & 0xfU) << 1),
                                            13);
    const std::uint32_t imm_u = instruction & 0xfffff000U;
    const std::uint32_t imm_j = sign_extend(((instruction >> 31) << 20) |
                                                (((instruction >> 12) & 0xffU) << 12) |
                                                (((instruction >> 20) & 1U) << 11) |
                                                (((instruction >> 21) & 0x3ffU) << 1),
                                            21);

    RetireTrace trace;
    trace.valid = true;
    trace.pc = pc_;
    trace.instruction = instruction;
    trace.target = pc_ + 4;
    std::uint32_t next_pc = pc_ + 4;
    std::uint32_t result = 0;
    bool write_rd = false;

    switch (opcode) {
    case 0x37:  // LUI
        result = imm_u;
        write_rd = true;
        break;
    case 0x17:  // AUIPC
        result = pc_ + imm_u;
        write_rd = true;
        break;
    case 0x6f:  // JAL
        result = pc_ + 4;
        write_rd = true;
        next_pc = pc_ + imm_j;
        trace.taken = true;
        trace.target = next_pc;
        break;
    case 0x67:  // JALR
        if (funct3 != 0) {
            return raise_trap(instruction, TrapCause::illegal_instruction);
        }
        result = pc_ + 4;
        write_rd = true;
        next_pc = (lhs + imm_i) & ~std::uint32_t{1};
        trace.taken = true;
        trace.target = next_pc;
        break;
    case 0x63: {  // BRANCH
        bool take = false;
        switch (funct3) {
        case 0: take = lhs == rhs; break;
        case 1: take = lhs != rhs; break;
        case 4: take = as_signed(lhs) < as_signed(rhs); break;
        case 5: take = as_signed(lhs) >= as_signed(rhs); break;
        case 6: take = lhs < rhs; break;
        case 7: take = lhs >= rhs; break;
        default: return raise_trap(instruction, TrapCause::illegal_instruction);
        }
        trace.taken = take;
        if (take) {
            next_pc = pc_ + imm_b;
        }
        trace.target = next_pc;
        break;
    }
    case 0x03: {  // LOAD
        const std::uint32_t address = lhs + imm_i;
        std::size_t bytes = 0;
        switch (funct3) {
        case 0:
        case 4: bytes = 1; break;
        case 1:
        case 5: bytes = 2; break;
        case 2: bytes = 4; break;
        default: return raise_trap(instruction, TrapCause::illegal_instruction);
        }
        if ((bytes == 2 && (address & 1U)) || (bytes == 4 && (address & 3U))) {
            return raise_trap(instruction, TrapCause::load_address_misaligned);
        }
        if (!range_ok(address, bytes)) {
            return raise_trap(instruction, TrapCause::load_access_fault);
        }
        if (funct3 == 0) {
            result = sign_extend(memory_[address], 8);
        } else if (funct3 == 1) {
            result = sign_extend(read_u16(address), 16);
        } else if (funct3 == 2) {
            result = read_u32(address);
        } else if (funct3 == 4) {
            result = memory_[address];
        } else {
            result = read_u16(address);
        }
        write_rd = true;
        break;
    }
    case 0x23: {  // STORE
        const std::uint32_t address = lhs + imm_s;
        std::size_t bytes = 0;
        if (funct3 == 0) bytes = 1;
        else if (funct3 == 1) bytes = 2;
        else if (funct3 == 2) bytes = 4;
        else return raise_trap(instruction, TrapCause::illegal_instruction);
        if ((bytes == 2 && (address & 1U)) || (bytes == 4 && (address & 3U))) {
            return raise_trap(instruction, TrapCause::store_address_misaligned);
        }
        if (!range_ok(address, bytes)) {
            return raise_trap(instruction, TrapCause::store_access_fault);
        }
        trace.memory_write = true;
        trace.memory_address = address;
        trace.memory_data = rhs;
        trace.memory_strobe = bytes == 1 ? 0x1 : (bytes == 2 ? 0x3 : 0xf);
        if (bytes == 1) write_u8(address, static_cast<std::uint8_t>(rhs));
        else if (bytes == 2) write_u16(address, static_cast<std::uint16_t>(rhs));
        else write_u32(address, rhs);
        break;
    }
    case 0x13:  // OP-IMM
        write_rd = true;
        switch (funct3) {
        case 0: result = lhs + imm_i; break;
        case 2: result = as_signed(lhs) < as_signed(imm_i); break;
        case 3: result = lhs < imm_i; break;
        case 4: result = lhs ^ imm_i; break;
        case 6: result = lhs | imm_i; break;
        case 7: result = lhs & imm_i; break;
        case 1:
            if (funct7 != 0) return raise_trap(instruction, TrapCause::illegal_instruction);
            result = lhs << (rs2 & 31U);
            break;
        case 5:
            if (funct7 == 0) result = lhs >> (rs2 & 31U);
            else if (funct7 == 0x20) result = static_cast<std::uint32_t>(as_signed(lhs) >> (rs2 & 31U));
            else return raise_trap(instruction, TrapCause::illegal_instruction);
            break;
        default: return raise_trap(instruction, TrapCause::illegal_instruction);
        }
        break;
    case 0x33:  // OP
        write_rd = true;
        switch (funct3) {
        case 0:
            if (funct7 == 0) result = lhs + rhs;
            else if (funct7 == 0x20) result = lhs - rhs;
            else return raise_trap(instruction, TrapCause::illegal_instruction);
            break;
        case 1:
            if (funct7 != 0) return raise_trap(instruction, TrapCause::illegal_instruction);
            result = lhs << (rhs & 31U);
            break;
        case 2:
            if (funct7 != 0) return raise_trap(instruction, TrapCause::illegal_instruction);
            result = as_signed(lhs) < as_signed(rhs);
            break;
        case 3:
            if (funct7 != 0) return raise_trap(instruction, TrapCause::illegal_instruction);
            result = lhs < rhs;
            break;
        case 4:
            if (funct7 != 0) return raise_trap(instruction, TrapCause::illegal_instruction);
            result = lhs ^ rhs;
            break;
        case 5:
            if (funct7 == 0) result = lhs >> (rhs & 31U);
            else if (funct7 == 0x20) result = static_cast<std::uint32_t>(as_signed(lhs) >> (rhs & 31U));
            else return raise_trap(instruction, TrapCause::illegal_instruction);
            break;
        case 6:
            if (funct7 != 0) return raise_trap(instruction, TrapCause::illegal_instruction);
            result = lhs | rhs;
            break;
        case 7:
            if (funct7 != 0) return raise_trap(instruction, TrapCause::illegal_instruction);
            result = lhs & rhs;
            break;
        default: return raise_trap(instruction, TrapCause::illegal_instruction);
        }
        break;
    case 0x0f:  // FENCE is a serialization no-op in the flat-memory model.
        if (funct3 != 0) return raise_trap(instruction, TrapCause::illegal_instruction);
        break;
    case 0x73:
        if (instruction == 0x00000073U) {
            return raise_trap(instruction, TrapCause::environment_call);
        }
        if (instruction == 0x00100073U) {
            return raise_trap(instruction, TrapCause::breakpoint);
        }
        return raise_trap(instruction, TrapCause::illegal_instruction);
    default:
        return raise_trap(instruction, TrapCause::illegal_instruction);
    }

    if ((next_pc & 3U) != 0) {
        return raise_trap(instruction, TrapCause::instruction_address_misaligned);
    }
    if (write_rd && rd != 0) {
        registers_[rd] = result;
        trace.rd_write = true;
        trace.rd = static_cast<std::uint8_t>(rd);
        trace.rd_value = result;
    }
    registers_[0] = 0;
    pc_ = next_pc;
    return trace;
}

BranchPredictor::BranchPredictor(std::size_t entries) : entries_(entries) {
    if (entries == 0 || (entries & (entries - 1)) != 0) {
        throw std::invalid_argument("predictor entry count must be a power of two");
    }
    reset();
}

void BranchPredictor::reset() {
    for (auto& entry : entries_) {
        entry = {};
        entry.counter = 1;
    }
}

std::size_t BranchPredictor::index(std::uint32_t pc) const {
    return (pc >> 2) & (entries_.size() - 1);
}

Prediction BranchPredictor::predict(std::uint32_t pc) const {
    const Entry& entry = entries_[index(pc)];
    if (!entry.valid || entry.tag != pc) {
        return {false, pc + 4};
    }
    const bool unconditional = entry.kind != BranchKind::conditional;
    const bool taken = unconditional || entry.counter >= 2;
    return {taken, taken ? entry.target : pc + 4};
}

void BranchPredictor::update(std::uint32_t pc, bool taken, std::uint32_t target,
                             BranchKind kind) {
    Entry& entry = entries_[index(pc)];
    if (!entry.valid || entry.tag != pc) {
        entry.valid = true;
        entry.tag = pc;
        entry.target = target;
        entry.kind = kind;
        entry.counter = taken ? 2 : 1;
        return;
    }
    entry.target = target;
    entry.kind = kind;
    if (taken && entry.counter < 3) ++entry.counter;
    if (!taken && entry.counter > 0) --entry.counter;
}

}  // namespace rv32

