# Decoupled RV32I Tomasulo CPU

This directory contains the canonical, single-issue RV32I out-of-order core. The former three-block and shared-bus implementations were retired after being preserved in Git baseline commit `90178b7`.

## What is implemented

- Explicit fetch frontend with one outstanding request, stale-response cancellation, BTB, and 2-bit BHT.
- Pure combinational RV32I decoder.
- RAT-based rename with per-control-flow checkpoints.
- Eight-entry ROB, integer/branch reservation station, and LSQ.
- Out-of-order integer, branch, and memory execution with in-order precise commit.
- Branch/JAL/JALR prediction, redirect, younger-uop squash, and RAT restore.
- Byte, halfword, and word loads/stores with signed and unsigned loads.
- Precise illegal-instruction, ECALL/EBREAK, instruction-access, and misalignment halt/trap reporting.
- Decoupled instruction/data memory request-response ports.
- C++ architectural model and self-checking Verilator regression.

The initial platform intentionally excludes privileged CSRs, interrupts, RV32M/A/F/D/C/V, caches, MMU, multiple issue, and hardware support for misaligned data accesses.

## Module map

- `rtl/rv32_frontend.sv`: PC, fetch buffering, predictor, redirects.
- `rtl/rv32_decode.sv`: RV32I decode to a typed uop.
- `rtl/rv32_rename.sv`: register file, RAT, dependency lookup, checkpoints.
- `rtl/rv32_rob.sv`: allocation, completion state, squash, precise retirement.
- `rtl/rv32_int_rs.sv`: integer/branch reservation station and ready selection.
- `rtl/rv32_alu_branch.sv`: integer execution and control-flow resolution.
- `rtl/rv32_lsq.sv`: memory dependency tracking and committed-store retention.
- `rtl/rv32_lsu.sv`: external data-memory protocol and load formatting.
- `rtl/rv32_writeback.sv`: completion-stream arbitration.
- `rtl/rv32_ooo_core.sv`: handshake composition only; it owns no backend arrays.
- `rtl/rv32_simple_soc.sv`: simulation-only memory adapter.
- `hpp/` and `cpp/`: architectural reference model.
- `tests/`: C++ and RTL self-checking tests.

Detailed interface and recovery rules are in [`docs/architecture.md`](docs/architecture.md). The approved milestones are in [`docs/project_plan.md`](docs/project_plan.md).

## Run verification

Requirements: `g++`, GNU Make, and Verilator.

```sh
make model-test
make rtl-lint
make rtl-test
```

`make rtl-test` runs three programs covering speculation/recovery, RV32I ALU and memory widths, JAL/JALR, ROB tag wraparound, wrong-path store/halt suppression, and precise misaligned-load trapping.

## Repository snapshot

This repository starts from a reviewed source snapshot. Commit references in older design notes refer to the original workspace history, which is not imported here. Generated simulation output and local environment files are excluded.
