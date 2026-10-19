# Tests

This project was built test-first, bottom-up, each layer gating the next.
All tests use [Hypothesis](https://hypothesis.readthedocs.io/) for
property-based generation and run the actual compiled Metal kernels
in-process via [PyObjC](https://pyobjc.readthedocs.io/)'s Metal bindings --
no separate test harness binary needed.

## Setup

Run these from the **repo root** (not from inside `tests/`) -- the tests
open `fe25519.metal` and `base_table.bin` with paths relative to the
current directory, so pytest needs to be invoked from the root where those
files actually live:

```
python3 -m venv tests/.venv
./tests/.venv/bin/pip install pytest hypothesis cryptography 'pyobjc-framework-Metal==11.1' 'pyobjc-framework-Cocoa==11.1'
./tests/.venv/bin/pytest tests/ -v
```

(Pinning pyobjc to 11.1: at the time of writing, pip's default resolver
picks a 12.0 pre-release that was yanked from PyPI and has no prebuilt
wheel for this platform, so it falls back to a slow from-source build.
11.1 has prebuilt wheels and installs in seconds.)

## What each file checks, and against what

- **`test_fe25519.py`** -- field arithmetic (add/sub/mul/square/invert,
  canonical encode/decode) against Python's native arbitrary-precision
  integers, including explicit boundary cases (`p`, `p + 18`, and the
  top bit that the encoding ignores).
- **`test_point.py`** -- scalar multiplication by the base point against
  `edwards_ref.py`, a deliberately simple, from-scratch Edwards-curve
  implementation written directly from the curve equations (not optimized,
  easy to eyeball-verify).
- **`edwards_ref.py`** is itself validated, at the bottom of the file under
  `if __name__ == "__main__"`, against the real `cryptography` library's
  Ed25519 key derivation across 20 random seeds -- it's only trustworthy as
  an oracle because of that check.
- **`test_sha512.py`** -- the SHA-512 implementation against Python's
  `hashlib.sha512`, plus boundary examples.
- **`test_derive.py`** -- **the real correctness gate**: the full
  seed → pubkey pipeline against the `cryptography` library directly,
  across thousands of random seeds, including a batched (512-thread)
  dispatch to make sure per-thread parallelism itself is correct and not
  just single-thread execution.
- **`test_table.py`** -- the precomputed-table scalar multiplication
  (the performance optimization) against both the `cryptography` oracle
  and the original double-and-add implementation directly, so the
  optimization is checked against two independent things, not just "does
  it still pass the same test as before."
- **`test_grind.py`** -- the base64 encoder against Python's `base64`
  module, and the suffix-matching/atomic-counter logic in the actual grind
  kernel, checked by deriving a real batch of pubkeys, picking real
  suffixes off it as the search targets, and confirming the kernel flags
  exactly those seeds and no others -- no brute-force searching needed to
  construct the test. Includes a dedicated mixed-length-targets test (a
  3-char and a 15-char target searched for in the same dispatch), since
  the kernel and host both need to agree on how target lengths are
  represented -- see "Things this process actually caught" below for a
  bug this exact concern turned up.
- **`test_plumbing.py`** -- a trivial pass-through kernel, there only to
  prove the PyObjC/Metal/Hypothesis plumbing itself works before any real
  crypto code was written.

## Things this process actually caught

- A real memory leak in the Swift host harness: Metal buffers/command
  buffers/encoders are Objective-C objects, and a bare command-line tool
  has no run loop to drain the autorelease pool, so every loop iteration's
  objects piled up until an explicit `autoreleasepool { }` per iteration
  fixed it.
- The precomputed base-point table was expected to roughly triple
  throughput (three times fewer point operations per key). It measured at
  about a 10% improvement instead -- which turned out to be a genuinely
  useful finding: the kernel is occupancy/register-bound, not
  arithmetic-throughput-bound, so reducing the amount of math per thread
  doesn't translate into proportionally more GPU parallelism. Closing that
  gap further would mean shrinking the kernel's per-thread register/stack
  footprint, not more precomputation.
- When target lengths became variable instead of fixed, the Swift host
  packed each target's length as a big-endian `UInt32` (the convention
  used elsewhere in this codebase for the actual SSH wire format, where
  big-endian really is required by the protocol) -- but the kernel reads
  that buffer as a plain native `uint`, which is little-endian on this
  hardware. Every length got corrupted into a huge garbage value and
  silently skipped, so nothing ever matched. The pytest suite didn't catch
  it, because its Python-side test harness packed the same buffer with
  native byte order from the start (`struct.pack("I", ...)` with no
  explicit endianness). Only a full Swift-level smoke test -- injecting a
  known-matching seed and running the real compiled binary end-to-end --
  caught it. That's why this project keeps doing that extra check after
  any change to how the Swift host and the kernel agree on a buffer
  layout, even when the kernel's own tests already pass.

## Performance investigation (post-launch)

Given the occupancy-bound finding above, a follow-up investigation looked
for ways to actually reduce the kernel's per-thread footprint rather than
its arithmetic operation count. Two things were tried, measured cleanly
(production job paused, ~60-90s per measurement, same batch size and
targets each time):

- **Threadgroup size.** The host had always requested the GPU-reported
  maximum (`pipeline.maxTotalThreadsPerThreadgroup`, 1024 on an M4). A
  sweep of 32/64/128/256/512/1024 found that every size from 32 to 512
  measured the same (~740-745k/s, within noise of each other), while 1024
  measured a consistent ~657-663k/s -- about 12% *slower*. This directly
  supports the occupancy-bound diagnosis: a register-heavy kernel at full
  threadgroup width leaves fewer threadgroups able to be resident
  concurrently per GPU core, so the "maximum" setting actively hurts
  throughput. 256 is now the default (`--threadgroup-size`), a pure
  host-side dispatch parameter with no kernel changes and no correctness
  risk at all.
- **SHA-512's message schedule.** `sha512_32` used to materialize the full
  80-entry `ulong w[80]` (640 bytes/thread) even though the recurrence
  only ever reads 4 specific prior entries. Replaced with a 16-entry
  rolling buffer (128 bytes/thread) -- the kind of fixed-size,
  wide-indexed local array SHA-512 produces is a known GPU anti-pattern,
  likely to end up in actual per-thread stack memory rather than
  registers. Re-verified against `hashlib.sha512` in isolation, then the
  full suite, before measuring. Result: **no measurable change** (~740k/s
  either way, once the threadgroup-size fix was already in place) --
  an honest null result. Kept anyway since it's strictly smaller,
  equally well-tested, and may matter more on different Apple Silicon
  generations with tighter register files; reported here rather than
  implied to have helped.

Net effect: ~605k/s (original double-and-add) → ~663k/s (precomputed
table) → **~740k/s (threadgroup-size fix)**, roughly 22% over the
table-only version and about 41% over the original naive port.

**What would likely help further, and why it wasn't pursued here:** real
GPU register/occupancy profiling needs Xcode's GPU Frame Capture / Metal
System Trace (Instruments), which requires the full Xcode install, not
just the Command Line Tools used throughout this project. Without it,
further register-pressure reduction (e.g. in the point-arithmetic
temporaries) would be guesswork rather than measurement-driven, which is
exactly the kind of unverified change this project has tried to avoid.
