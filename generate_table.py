#!/usr/bin/env python3
"""Regenerates base_table.bin: 256 entries of 64 bytes each, the affine
(x, y) coordinates of 2^i * B for i=0..255, where B is the standard
Ed25519 base point. The Metal grinder uses this as a precomputed lookup
table so its scalar-multiplication loop needs only one point *addition*
per set bit of the scalar, instead of an unconditional doubling for every
bit regardless of its value.

Only needs Python's standard library (no dependencies). See tests/README.md
for how this table -- and every other piece of this implementation -- was
checked against known-good references before being trusted.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent / "tests"))
from edwards_ref import point_double, Bx, By  # noqa: E402


def main():
    points = []
    P = (Bx, By)
    for _ in range(256):
        points.append(P)
        P = point_double(P)

    out_path = Path(__file__).parent / "base_table.bin"
    with open(out_path, "wb") as f:
        for (x, y) in points:
            f.write(x.to_bytes(32, "little"))
            f.write(y.to_bytes(32, "little"))

    print(f"wrote {out_path} ({256 * 64} bytes)")


if __name__ == "__main__":
    main()
