# RV32I OoO CPU Project Plan

## Objective

Replace the demonstration-only Tomasulo design with a synthesizable, single-issue RV32I core whose frontend and backend communicate through explicit valid/ready transactions. Each stateful block owns its state; the integration layer performs arbitration only and never writes another block's internal arrays.

## Approved Scope

- RV32I user-level integer instructions.
- One-wide fetch, decode, rename/dispatch, and commit.
- Tomasulo-style out-of-order integer, branch, and memory execution.
- In-order precise retirement through a ROB.
- Explicit fetch and data-memory ready/valid interfaces.
- BTB plus 2-bit direction predictor; prediction correctness is isolated from recovery correctness.
- Branch/JAL/JALR resolution, frontend redirect, younger-uop squash, and RAT checkpoint restore.
- Loads and stores of byte, halfword, and word widths.
- Misaligned accesses produce a precise trap/halt indication in the initial implementation.
- ECALL/EBREAK and illegal instructions retire as a test-visible halt/trap; privileged CSRs and interrupts are out of scope.

## Architectural Boundaries

| Block | Owns | Communicates Through |
| --- | --- | --- |
| Frontend | PC, outstanding fetch, IF buffer, predictor tables | instruction-memory request/response, fetch packet, redirect, predictor update |
| Decoder | no state | fetch packet and decoded-uop packet |
| Rename | architectural register file, RAT, branch checkpoints | source queries to ROB, dispatch update, commit write, completion bypass, recovery |
| ROB | allocation order and retirement state | allocation offer, dispatch, two source queries, completion, commit, recovery |
| Integer RS | waiting integer/branch uops | dispatch, completion broadcast, issue transaction, recovery |
| ALU/branch unit | one output pipeline register | issue and completion transactions |
| LSQ | waiting memory uops and memory ordering | dispatch, wakeup, load request, store-address completion, commit release, recovery |
| LSU | one memory transaction | committed-store/load arbitration, data-memory request/response, load completion |
| Writeback | arbitration only | completion streams and one broadcast stream |
| Core integration | handshake composition only | public memory, retirement, halt/trap, and performance signals |

## Interface Rules

- A transfer occurs only on `valid && ready`.
- Producers hold payload stable while `valid && !ready`.
- Dispatch is atomic across ROB, rename, and exactly one destination queue; partial allocation is forbidden.
- Recovery has priority over dispatch and normal pipeline advance.
- Stores reach the external memory interface only after their ROB entry reaches commit.
- Wrong-path uops may execute but may not retire, update memory, or train the predictor.
- Completion broadcasts identify the destination by ROB tag and carry a monotonically increasing sequence number for squash comparisons.
- Simulation-only memory arrays and HEX loading stay outside the core.

## Milestones and Exit Criteria

### M0: Reproducible Baseline

- Source-only baseline exists on a dedicated branch.
- Generated simulator artifacts are ignored.
- Existing failing UVM result is recorded as a known baseline defect.

Exit: original source can be recovered without relying on generated files.

### M1: Architectural Reference Model

- C++ RV32I model implements the approved instruction behavior.
- Unit tests cover arithmetic, immediates, branches/jumps, memory widths, and halt/trap behavior.
- Predictor unit tests cover cold miss, counter training, taken prediction, and target replacement.

Exit: all C++ tests pass with `g++`.

### M2: Decoupled Frontend and Decode

- Frontend has a one-entry IF buffer and one outstanding memory request.
- Redirects invalidate stale responses.
- Decoder covers RV32I and flags unsupported encodings.
- BTB/BHT prediction metadata travels with the instruction.

Exit: decoder and frontend RTL tests pass under backpressure and redirect scenarios.

### M3: Decoupled OoO Backend

- ROB, rename, RS, ALU/branch, LSQ, LSU, and writeback own their state.
- Atomic dispatch and completion wakeup are verified.
- Store side effects occur only at commit.
- Existing straight-line arithmetic/load/store program passes.

Exit: retirement trace matches the C++ model for directed dependency and memory tests.

### M4: Speculation and Recovery

- Conditional branches and jumps may be predicted.
- Mispredict redirects fetch and squashes every younger ROB/RS/LSQ/LSU operation.
- RAT restore preserves the resolving branch and all older architectural mappings.
- Wrong-path store, halt, and predictor update tests pass.

Exit: alternating, nested, forward, and backward branch programs match the C++ model.

### M5: RV32I Completion and Quality Gates

- Remaining RV32I operations and memory widths pass directed tests.
- Verilator lint has no errors.
- Self-checking RTL regression passes.
- README and architecture documentation match implemented behavior.

Exit: C++ model tests, RTL directed tests, lint, and synthesis-oriented elaboration all pass.

## Verification Strategy

- Use the C++ model as the architectural oracle.
- Compare retirement PC, instruction, destination register/value, and committed memory writes.
- Add SystemVerilog assertions for x0, ROB occupancy, atomic dispatch, stable valid/ready payloads, unique live ROB tags, and no wrong-path commit.
- Cover predictor hit/miss and correct/incorrect outcomes, ROB/RS/LSQ pressure, simultaneous completion/commit/dispatch, and recovery with every uop class younger than the branch.
- Keep Questa UVM as an optional integration environment; use Verilator for portable lint and automated self-checking regression.

## Explicit Non-Goals

- RV32M/A/F/D/C/V extensions.
- Privileged architecture, CSRs, interrupts, MMU, caches, or coherence.
- Multiple issue or multiple commit.
- Hardware handling of misaligned data accesses.
- Fault-coverage claims from functional coverage.

## Rollback and Change Discipline

- Each milestone is independently reviewable and testable.
- The legacy core remains available until the new core passes its matching baseline test.
- Do not duplicate behavioral logic between `rtl/` and `rtl_bus/`; compatibility variants must instantiate the canonical core.
- Generated objects, simulator databases, waveforms, and logs are never authoritative sources.
