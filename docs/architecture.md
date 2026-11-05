# Decoupled RV32I OoO Architecture

## Dataflow

```text
 instruction memory
        ^   |
        |   v
 +-------------+   fetch packet   +--------+   decoded uop
 |  frontend   |----------------->| decode |------------------+
 | BTB + BHT   |<--- redirect ----+--------+                  |
 +-------------+                                               v
                    +-------- source queries --------+   +------------+
                    |                                |   | rename /   |
                    v                                |   | dispatch   |
                 +------+                            |   +------------+
                 | ROB  |<------ completion ---------+          |
                 +------+                                       |
                    | commit                     atomic dispatch |
                    v                                           v
              architectural RF             +---------+     +---------+
                                            | int RS  |     |  LSQ    |
                                            +---------+     +---------+
                                                 |               |
                                                 v               v
                                            +----------+    +---------+
                                            | ALU/BR   |    |  LSU    |<-> data memory
                                            +----------+    +---------+
                                                  \             /
                                                   +-----------+
                                                   | writeback |
                                                   +-----------+
```

The core integration module connects handshakes and chooses atomic dispatch readiness. It does not read or write module-owned arrays.

## Transaction rules

- Payload transfer occurs on `valid && ready` only.
- A producer holds payload stable while stalled.
- Decode is stateless. Frontend, rename, ROB, RS, LSQ, LSU, and execution pipeline state have single owners.
- Dispatch allocates the ROB and exactly one execution queue in the same cycle or allocates nothing.
- Dependencies use both a circular ROB tag and a 32-bit sequence number. The sequence number prevents an old generation of a wrapped tag from waking or clearing a new generation.
- Completion arbitration emits one broadcast per cycle. Waiting operands match `{rob_tag, seq_num}`.
- Stores calculate address/data out of order but remain in the LSQ and update external memory only when the ROB commits them.

## Fetch and prediction

The frontend permits one outstanding instruction request and one buffered response. Each request records an epoch bit. A redirect toggles the epoch and clears the fetch buffer; a later response from the old epoch is consumed and discarded.

The predictor contains 16 direct-mapped entries by default:

- full-PC tag and target in the BTB;
- 2-bit saturating counter for conditional direction;
- unconditional prediction for learned JAL/JALR entries.

Prediction metadata travels with the instruction into the ROB. Predictor updates occur only when a non-squashed control-flow instruction commits.

## Rename and recovery

The RAT maps each architectural source to `{ROB tag, sequence}`. A source is supplied from the architectural register file, a ready ROB entry, or the current completion bypass; otherwise it is dispatched as a tagged dependency.

Every branch, JAL, and JALR saves a RAT checkpoint that includes the control instruction's own destination mapping. Commit events also update active checkpoints, including same-cycle commit plus checkpoint creation, so a checkpoint never restores a producer that has already retired.

When control flow resolves incorrectly:

1. ALU/branch completion supplies actual next PC and the resolving sequence number.
2. Frontend redirects and invalidates stale fetch state.
3. ROB keeps the resolving entry and every older entry, invalidating younger entries.
4. RS, LSQ, and an outstanding LSU result discard entries with a greater sequence number.
5. Rename restores the resolving instruction's checkpoint and discards its checkpoint plus all younger checkpoints.

The resolving control instruction later commits normally and trains the predictor.

## Memory ordering

- Loads wait while any older store remains in the LSQ.
- This conservative policy is correct but does not yet implement store-to-load forwarding.
- A load leaves the LSQ only when the LSU accepts it.
- A store reports address/data readiness to the ROB, remains in the LSQ, and leaves only at commit.
- Byte-lane shifts and strobes are generated before the committed store reaches the external interface.
- Misaligned halfword/word accesses complete with a precise trap and do not update a destination register or memory.

## Retirement and traps

The ROB commits at most one instruction per cycle. Register writes and predictor updates occur at commit; external stores additionally wait for LSU request readiness. ECALL, EBREAK, illegal instructions, instruction access faults, and data misalignment retire as a test-visible halt/trap. Once halted, no younger ROB entry may retire.

The retirement interface reports PC, instruction, register write, and committed memory write data for differential checking against the C++ model.

