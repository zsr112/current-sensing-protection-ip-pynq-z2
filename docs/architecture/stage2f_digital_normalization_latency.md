# Stage 2F-D Normalizer Latency Contract

```text
PRODUCTION_PROFILE=UNCONFIGURED
NORMALIZED_UNIT=SIGNED_CODE_COUNT
NORMALIZER_PIPELINE_LATENCY_ACLK=1
PIPELINE_INITIATION_INTERVAL=1
NO_DATA_DEPENDENT_LATENCY=YES
NO_BACKPRESSURE_TO_ATOMIC_CDC=YES
NO_TRANSACTION_DROP=YES
STAGE2F_CONTRACT_GAP_CLOSED=NO
PHYSICAL_SCALING_STATUS=BLOCKED_EXTERNAL_HARDWARE_FACTS
REMAINING_CONTRACT_GAPS=2
STAGE2_COMPLETE=NO
DATA_WIDTH_COMPATIBILITY_POLICY=RAW_GENERIC_NORMALIZATION_ONLY_AT_12
OBS_SEQUENCE_WIDTH_PROPAGATION=EXACT
```

The normalizer is one `ACLK`-registered stage. On an eligible destination
destination delivery at edge `n`, `normalized_valid`, sequence, and both signed 13-bit
channels are updated together after edge `n`; the published transaction is
consumed as the one-stage result at edge `n+1`. When no raw delivery occurs,
the valid bit is cleared and no new transaction is created. The arithmetic
path has no data-dependent branches that change this cycle count.

The stage accepts a new raw delivery on every ACLK edge while the profile is
valid. There is no ready signal, no feedback to the FIFO, and no way for a
normalized consumer to stall or drop the atomic raw transaction. Sequence and
channel values share the same register boundary, which makes the sequence the
identity for downstream telemetry alignment.

The one-cycle contract exists only in the `DATA_WIDTH=12` generate branch.
That branch binds the top's full `OBS_SEQUENCE_WIDTH` into the normalizer, so
16-, 24-, and 32-bit identities cross the register without resizing. For other
data widths there is no active normalization pipeline; all normalized state and
status are tied low while the raw transaction path continues independently.

The existing destination local reset clears valid, sequence, and both payload
registers. Reset therefore flushes an occupied stage, prevents a ghost output,
and permits exactly one normalized output for the first eligible transaction
after release. With the production `UNCONFIGURED` profile, the same reset and
latency machinery remains present but `normalized_valid` never asserts and
payload/sequence remain zero.

The latency value is an implementation-derived constant for this RTL, not a
physical sampling-rate or timing closure claim. Vivado timing and any future
normalized protection domain remain separate review gates.
