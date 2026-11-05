#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <vector>

namespace rv32 {

enum class TrapCause : std::uint32_t {
    none = 0,
    instruction_address_misaligned,
    instruction_access_fault,
    illegal_instruction,
    breakpoint,
    load_address_misaligned,
    load_access_fault,
    store_address_misaligned,
    store_access_fault,
    environment_call,
};

struct RetireTrace {
    bool valid = false;
    std::uint32_t pc = 0;
    std::uint32_t instruction = 0;
    bool rd_write = false;
    std::uint8_t rd = 0;
    std::uint32_t rd_value = 0;
    bool memory_write = false;
    std::uint32_t memory_address = 0;
    std::uint32_t memory_data = 0;
    std::uint8_t memory_strobe = 0;
    bool taken = false;
    std::uint32_t target = 0;
    bool trap = false;
    TrapCause cause = TrapCause::none;
};

class Rv32Model {
public:
    explicit Rv32Model(std::size_t memory_bytes = 64 * 1024);

    void reset(std::uint32_t reset_pc = 0);
    void load_word(std::uint32_t address, std::uint32_t value);
    std::uint32_t read_word(std::uint32_t address) const;
    RetireTrace step();

    const std::array<std::uint32_t, 32>& registers() const { return registers_; }
    std::uint32_t pc() const { return pc_; }
    bool halted() const { return halted_; }
    bool trapped() const { return trapped_; }
    TrapCause trap_cause() const { return trap_cause_; }

private:
    bool range_ok(std::uint32_t address, std::size_t bytes) const;
    std::uint16_t read_u16(std::uint32_t address) const;
    std::uint32_t read_u32(std::uint32_t address) const;
    void write_u8(std::uint32_t address, std::uint8_t value);
    void write_u16(std::uint32_t address, std::uint16_t value);
    void write_u32(std::uint32_t address, std::uint32_t value);
    RetireTrace raise_trap(std::uint32_t instruction, TrapCause cause);

    std::vector<std::uint8_t> memory_;
    std::array<std::uint32_t, 32> registers_{};
    std::uint32_t pc_ = 0;
    bool halted_ = false;
    bool trapped_ = false;
    TrapCause trap_cause_ = TrapCause::none;
};

enum class BranchKind : std::uint8_t {
    conditional = 0,
    jump = 1,
    call = 2,
    ret = 3,
};

struct Prediction {
    bool taken = false;
    std::uint32_t target = 0;
};

class BranchPredictor {
public:
    explicit BranchPredictor(std::size_t entries = 16);

    void reset();
    Prediction predict(std::uint32_t pc) const;
    void update(std::uint32_t pc, bool taken, std::uint32_t target, BranchKind kind);

private:
    struct Entry {
        bool valid = false;
        std::uint32_t tag = 0;
        std::uint32_t target = 0;
        BranchKind kind = BranchKind::conditional;
        std::uint8_t counter = 1;
    };

    std::size_t index(std::uint32_t pc) const;

    std::vector<Entry> entries_;
};

}  // namespace rv32

