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
  kernel, checked by deriving a real batch of pubkeys, picking two of
  their *actual* suffixes as the search targets, and confirming the
  kernel flags exactly those two seeds and no others -- no brute-force
  searching needed to construct the test.
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
