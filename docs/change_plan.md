# Change Plan

## Change Summary
- Refactor the current Tomasulo demonstration core into a clearly staged, single-issue RV32I out-of-order CPU.
- Introduce explicit fetch, prediction, decode, rename/dispatch, scheduling/execution, writeback, recovery, and in-order commit boundaries with valid/ready flow control.
- Add control-flow execution and speculative recovery before enabling a dynamic branch predictor.
- Consolidate the duplicated `rtl/` and `rtl_bus/` implementations into one canonical design and remove shared mutable-state interfaces from module boundaries.
- Establish a passing architectural reference-model regression before extending the instruction set or changing the microarchitecture.

## Change Reason
- The current design is not a complete RV32 CPU. It implements only a small subset: ADD/SUB/AND/OR/XOR, ADDI, LW, SW, and a custom ECALL-as-halt behavior.
- Fetch is currently an inline combinational expression in the top module (`instr = imem[pc >> 2]`), not a frontend module or pipeline stage.
- Decode exists, but it is embedded in `ioi_issue.sv` together with resource checks, operand lookup, rename, and dispatch. This makes frontend control, backpressure, illegal-instruction handling, and control-flow recovery difficult to reason about.
- PC movement is tied directly to issue success and otherwise only advances by four. There is no branch, JAL/JALR, redirect, prediction, squash, or RAT recovery path.
- The current execution block combines ready-entry selection, ALU execution, memory-address generation, memory access, and CDB arbitration in one combinational block; the design therefore has module names but not a well-defined latency pipeline.
- The recorded UVM run is not a clean baseline: it reports `mem0 mismatch 13`, `mem1 mismatch 0`, and proxy coverage of 77.78%.
- Unsupported nonzero instructions are silently skipped by `issue_advance_without_issue`, which can hide decode gaps as successful forward progress.
- `rtl/` and `rtl_bus/` duplicate the same architecture and have already drifted. The bus top also contains a malformed/mis-scoped `if` block in CDB wakeup logic, demonstrating the maintenance risk of parallel copies.

## Current Design Context
- The folder is currently untracked under the parent repository, so there is no committed baseline or isolated rollback point for this design.
- `tomasuli_ooo_cpu_top.sv` owns almost all architectural and microarchitectural state: PC, register file, RAT, ROB, RS, LSQ, instruction memory, and data memory.
- `ioi_issue.sv` performs instruction field extraction, partial decoding, resource admission, source lookup/forwarding, rename tagging, and RS/LSQ dispatch combinationally.
- `ooo_execute.sv` selects one ready RS operation and one ready LSQ operation, gives loads priority on the single CDB, and blocks every load behind any older store. It has no forwarding from older stores and no byte-enable/alignment behavior.
- `ioc_commit.sv` is only a combinational view of the ROB head. The top module performs all state mutation and retirement effects.
- The current top-level memory model is simulation-oriented: internal unpacked arrays, a hard-coded Windows HEX default path, direct hierarchical testbench deposits, and word-indexed accesses without a bus protocol.
- Working interpretation for this plan: target a synthesizable RV32I integer core, one instruction fetched/decoded/dispatched/committed per cycle at most, with a small Tomasulo-style out-of-order backend and precise in-order retirement. This assumption requires approval or adjustment before implementation.

## Impact Analysis

### Interfaces
- Replace direct array sharing and very wide state plumbing with typed request/response bundles between stages.
- Define a frontend instruction-memory interface with request address, request valid/ready, response instruction, response PC, response valid/ready, and fault indication. Keep a small simulation memory adapter outside the CPU core.
- Define a decoded-uop bundle carrying PC, instruction, source/destination registers, immediate, functional-unit class, ALU/branch/memory operation, writeback intent, exception metadata, and prediction metadata.
- Define dispatch interfaces to ROB, integer RS, branch RS/execution, and LSQ, with atomic allocation readiness so a uop cannot be partially admitted.
- Define execution completion packets carrying ROB tag, result, exception, branch outcome/target, and memory metadata. Replace implicit CDB priority with explicit arbitration.
- Define redirect/recovery signals from branch resolution and commit-time exceptions to frontend, ROB, RAT, RS, and LSQ.
- Preserve a small compatibility wrapper only if the existing `halted`, `committed_cnt`, and internal-memory test interface is still required.

### Functionality
- Implement the RV32I base integer instruction set: LUI, AUIPC, JAL, JALR, all conditional branches, OP-IMM, OP, byte/half/word loads, and byte/half/word stores.
- Treat FENCE as a serialization/no-op policy appropriate to the chosen memory model; define ECALL/EBREAK and illegal-instruction behavior explicitly rather than silently skipping them.
- Add branch target generation, condition evaluation, prediction metadata capture, misprediction detection, frontend redirect, and younger-uop squash.
- Make architectural side effects precise: stores update memory only at commit; wrong-path register, memory, predictor, and halt effects must not survive recovery.
- Add load/store width, sign/zero extension, byte enables, alignment checks, and address-range/error behavior.
- Decide whether Zicsr, interrupts, privilege modes, and traps are outside the first milestone. A core may be RV32I instruction-complete without being a privileged-system CPU.

### Module Decomposition and Architecture
- Proposed canonical structure:

  | Block | Responsibility |
  | --- | --- |
  | `rv32_frontend` | PC generation, fetch request/response, predictor lookup, redirect handling, IF queue |
  | `rv32_branch_predictor` | BTB, direction predictor, optional RAS, update policy |
  | `rv32_decode` | Pure instruction decode and immediate generation; no state allocation |
  | `rv32_rename_dispatch` | RAT lookup/update, source-tag/value formation, atomic ROB/RS/LSQ admission |
  | `rv32_rob` | Age order, completion state, precise retirement, squash boundary, exception metadata |
  | `rv32_int_rs` | Integer/branch reservation stations and age-aware ready selection |
  | `rv32_alu_branch` | Integer ALU, branch condition/target, branch resolution packet |
  | `rv32_lsq` | Ordered memory operations, address/data readiness, store-to-load forwarding policy |
  | `rv32_lsu` | Data-memory protocol, width/alignment handling, load formatting |
  | `rv32_writeback` | Completion arbitration and operand wakeup broadcasts |
  | `rv32_recovery` | Mispredict/exception squash and RAT restoration/checkpoint handling |
  | `rv32_commit` | In-order retirement, architectural register write, committed stores, predictor training |
  | `rv32_ooo_core` | Integration only; no large monolithic state-update process |

- Recommended recovery strategy for the small initial core: store a RAT checkpoint for each unresolved branch, then restore that checkpoint and invalidate all younger ROB/RS/LSQ entries on misprediction. If checkpoint storage is considered too expensive, reconstructing the speculative RAT from surviving ROB entries is an alternative, but it creates a large recovery scan and more complicated corner cases.
- Keep predictor policy separate from correctness. First support control flow with a static not-taken prediction and fully verified recovery; then add a small BTB plus 2-bit BHT and optional RAS without changing backend correctness.
- Select one canonical RTL tree. The recommended default is to replace both behavioral copies with the explicit-port/typed-bundle implementation and retain any interface-based version only as a wrapper, not a second source of logic.

### Timing and State
- Add registered boundaries at minimum between fetch response and decode, decode and rename/dispatch, execution and writeback, and writeback and retirement-visible state.
- Every pipeline register or queue entry must carry `valid` and obey stall/flush priority. Recommended control priority is reset, architectural redirect/trap, branch mispredict recovery, downstream stall, then normal advance.
- Define latency contracts: integer ALU/branch one cycle, memory request/response decoupled, writeback arbitration explicit, commit one uop per cycle initially.
- Resolve same-cycle interactions explicitly: commit plus dispatch, completion plus operand capture, branch resolution plus younger completion, store commit plus load issue, and wraparound of ROB tags.
- ROB tags must not alias live operations after wraparound. Either prove count-based reuse is sufficient across all queues or add a generation bit to tags.
- Predictor updates should occur only from non-squashed branches, preferably at commit for simple precise behavior.
- Reset must invalidate all queues, predictor validity, checkpoints, pending memory transactions, and frontend responses; architectural x0 remains hardwired to zero.

## Affected Modules
| Module | Current Role | Proposed Impact | Required Action |
| --- | --- | --- | --- |
| `rtl/tomasuli_ooo_cpu_top.sv` | Owns nearly all state and sequencing | Replaced by integration-only core plus memory wrapper | Decompose state ownership and add stage interfaces |
| `rtl/ioi_issue.sv` | Partial decode, rename, operand read, dispatch | Split into pure decode and rename/dispatch | Replace after decoder/uop tests exist |
| `rtl/ooo_execute.sv` | RS/LSQ selection, ALU, memory access, CDB | Split into RS, ALU/branch, LSQ/LSU, and writeback arbiter | Replace incrementally |
| `rtl/ioc_commit.sv` | ROB-head combinational decision | Expand into ROB/commit ownership with precise state effects | Replace |
| `rtl_bus/*` | Duplicated interface-based implementation | Maintenance and correctness risk | Retire or reduce to wrappers after canonical core passes |
| `tb_uvm/*` | One directed eight-instruction internal-state test | Insufficient ISA, speculation, and recovery coverage | Rebuild around architectural retire/memory interfaces |
| `test/run_questa_uvm.do` | Compiles only the explicit-port variant | Must follow new file structure and test tiers | Update after approval |
| `README.md` | Describes current three-block organization | Architecture and supported-ISA claims become obsolete | Rewrite after implementation |
| `transcript` / generated `work/` | Stale simulator outputs | Not source artifacts and currently show failure | Exclude from source baseline; regenerate reports outside source tree |

## Artifact Impact

### C++ Model and Headers
- No C++ reference model exists in this folder.
- Add a small instruction-accurate RV32I reference model or integrate an established ISS adapter to compare retired PC/instruction/register writes and committed memory writes.
- Define shared instruction encodings, architectural state, memory access helpers, and trace records in headers if a local model is chosen.
- Add differential tests for straight-line execution, branches/jumps, load/store widths, illegal instructions, and randomized dependency chains.

### Chisel
- No Chisel implementation is present. No Chisel change is required unless the intended long-term source language is changed from SystemVerilog.
- If Chisel is selected later, do not maintain independent hand-written SystemVerilog behavior in parallel; generated RTL should have one authoritative source.

### RTL
- Add typed packages for uop, completion, memory, prediction, and retirement records.
- Implement the frontend, predictor, decoder, recovery mechanism, full RV32I ALU/branch functions, precise ROB, and width-aware LSU.
- Move simulation-only memories and HEX loading out of the synthesizable core.
- Remove silent skipping of unsupported instructions and emit an illegal-instruction completion/trap or a documented test halt policy.
- Eliminate duplicated behavioral sources in `rtl_bus/` once compatibility is demonstrated.

### Tests
- Phase 0 baseline: reproduce and fix the existing failing load/store test without changing the intended architectural result; add assertions for ROB count/head/tail, unique live tags, x0, store-at-commit, and no use-after-free of RS/LSQ entries.
- Decoder unit tests: cover every RV32I opcode/funct combination, all immediate formats, and illegal encodings.
- Frontend tests: sequential fetch, backpressure, redirects, stale response cancellation, BTB/BHT hit/miss/update, and RAS if enabled.
- Backend directed tests: RAW/WAR/WAW chains, ROB wraparound, simultaneous commit/dispatch/completion, CDB contention, branch depending on pending operands, and mispredict with younger ALU/load/store/halt operations.
- Memory tests: LB/LBU/LH/LHU/LW, SB/SH/SW, sign extension, byte lanes, address boundaries, older-store blocking/forwarding, and wrong-path store suppression.
- Architectural tests: run the official or equivalent `riscv-tests` RV32UI subset supported by the environment and compare a retirement trace against the reference model.
- Random tests: constrained instruction streams with bounded memory, branches, ROB pressure, and differential checking.
- Coverage: replace the current nine-condition proxy with instruction/operand/control-flow covergroups, branch prediction outcomes, ROB/RS/LSQ occupancy crosses, recovery events, and assertion coverage. Functional coverage is not fault coverage.
- Lint/elaboration: compile both supported wrappers, enforce warnings, and add a synthesizability check that excludes test-only hierarchical memory access.

### Documentation
- Create an architecture specification describing stage contracts, uop fields, ROB semantics, rename recovery, memory ordering, predictor organization, exceptions, and supported ISA.
- Add a block diagram and cycle-level examples for normal flow, backpressure, a cache/memory wait, and branch misprediction.
- Update README build/run instructions and remove the machine-specific default HEX path from the core contract.
- Document known exclusions such as CSRs, privileged modes, interrupts, atomics, multiplication/division, caches, and unaligned accesses, according to approved scope.

## Project Plan Impact
- Required.
- No `docs/project_plan.md` currently exists in this folder. After approval, create it and include:
  - target ISA and platform scope;
  - canonical source-tree decision;
  - baseline repair milestone;
  - frontend/decode/control-flow milestone;
  - precise recovery milestone;
  - RV32I completion milestone;
  - dynamic predictor milestone;
  - architectural regression and synthesis-quality gates;
  - explicit exit criteria for each milestone.

## Implementation Steps After Approval
1. Freeze and archive a reproducible baseline: add the currently untracked folder intentionally, exclude simulator products, run the existing regression, and record its failures.
2. Add a retirement trace and minimal RV32I reference-model harness so subsequent refactors have an architectural oracle.
3. Repair the current store/load ordering or bookkeeping defect and make the existing directed regression pass before structural changes.
4. Introduce a common RTL package and pure `rv32_decode` module; retain an adapter so the old issue path can consume decoded uops temporarily.
5. Extract frontend state into `rv32_frontend` with an IF queue and valid/ready instruction-memory adapter; preserve sequential PC behavior first.
6. Refactor ROB, RAT/rename-dispatch, RS, LSQ, writeback, and commit so each module owns its state and exposes narrow transactional interfaces.
7. Implement branches, JAL, and JALR with static not-taken prediction, branch execution metadata, precise younger-uop squash, PC redirect, and RAT restore; verify wrong-path side effects are impossible.
8. Complete remaining RV32I ALU, immediate, load/store width, and upper-immediate instructions; define FENCE, ECALL/EBREAK, illegal instruction, and alignment behavior.
9. Add BTB plus 2-bit BHT and, if approved, RAS. Measure correctness independently from prediction accuracy.
10. Retire or wrap `rtl_bus/`, update UVM and architectural regressions, run lint/elaboration/simulation/synthesis checks, and update documentation/project plan.

## Risks
- A broad rewrite could preserve the current visible arithmetic examples while introducing subtle ROB wraparound, same-cycle, or recovery bugs. Differential retirement checking and incremental adapters mitigate this.
- Branch prediction without precise rename and queue recovery would corrupt architectural state. Prediction must not be enabled before squash and RAT restoration are verified.
- The current LSQ is not sufficient for general RV32I memory behavior. Store/load ordering, forwarding, byte lanes, and memory response latency can materially expand scope.
- A shared SystemVerilog interface that exposes all internal arrays can reduce wiring but weakens ownership and allows multiple writers; typed transaction bundles are safer.
- The hard-coded internal memory model hides realistic fetch/data latency. Moving to decoupled interfaces may expose new stalls and stale responses.
- Full privileged RISC-V, interrupts, CSRs, atomics, caches, and MMU support would turn this into a much larger project. The first approved milestone should explicitly exclude or schedule them.
- The source folder is currently untracked, so rollback is weak until a clean baseline commit is made.

## Rollback Plan
- Before implementation, create a dedicated `codex/` branch and commit the current source-only baseline without generated `work/`, waveform, or transcript artifacts.
- Implement each milestone as a separate commit with a passing regression gate.
- Keep temporary adapters around the old explicit-port core until the matching new stage passes differential tests.
- If a milestone regresses behavior, revert only that milestone commit and keep the last passing architectural baseline; do not overwrite the original untracked files in place without versioning them first.

## Open Questions
- Is the first target exactly unprivileged RV32I, or must it include Zicsr, machine-mode traps/interrupts, or RV32M?
- Should the CPU expose simple instruction/data SRAM ports, a ready/valid memory protocol, or a standard bus such as Wishbone/AXI-Lite?
- Is dynamic branch prediction mandatory in the first functional milestone, or is the recommended sequence acceptable: static not-taken plus recovery first, then BTB/BHT and optional RAS?
- Is one-wide fetch/decode/dispatch/commit acceptable, or is a wider frontend/backend expected?
- Should misaligned loads/stores trap, or must hardware support them?
- Is Questa the required simulator, and are Verilator, lint, formal checks, or FPGA synthesis also required acceptance gates?
- May `rtl_bus/` be removed after compatibility testing, or must both public tops remain supported?
- Should ECALL continue to mean halt for tests, or should halt move to a testbench/tohost mechanism while ECALL becomes an architectural trap?

## Approval Status
- Approved by the user on 2026-08-25.
- Implementation constraint emphasized by the user: keep modules decoupled.
