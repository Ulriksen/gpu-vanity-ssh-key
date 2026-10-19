import hashlib
import pytest
from hypothesis import given, settings, example, strategies as st
from metal_harness import MetalRunner

settings.register_profile("gpu", deadline=None)
settings.load_profile("gpu")

msg32 = st.binary(min_size=32, max_size=32)


@pytest.fixture(scope="session")
def runner():
    return MetalRunner("fe25519.metal")


@example(msg=bytes(32))                 # all-zero
@example(msg=bytes([0xff] * 32))        # all-ones
@example(msg=bytes(range(32)))          # 0x00..0x1f
@given(msg=msg32)
@settings(max_examples=1000)
def test_sha512_32(runner, msg):
    [out] = runner.run("k_sha512_32", [msg], [64], 1)
    assert out == hashlib.sha512(msg).digest()


def test_sha512_known_answer(runner):
    # NIST-style KAT: SHA-512("") padded/truncated is not 32 bytes, so use a
    # fixed well-known 32-byte message instead and just cross-check hashlib,
    # which is itself the trusted stdlib implementation.
    msg = b"abcdefghijklmnopqrstuvwxyz012345"[:32]
    assert len(msg) == 32
    [out] = runner.run("k_sha512_32", [msg], [64], 1)
    assert out == hashlib.sha512(msg).digest()
