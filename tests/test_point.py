import pytest
from hypothesis import given, settings, example, strategies as st
from metal_harness import MetalRunner
import edwards_ref as ref

settings.register_profile("gpu", deadline=None)
settings.load_profile("gpu")

scalar_bytes = st.binary(min_size=32, max_size=32)


@pytest.fixture(scope="session")
def runner():
    return MetalRunner("fe25519.metal")


def oracle_scalarmult(scalar_le_bytes: bytes) -> bytes:
    k = int.from_bytes(scalar_le_bytes, "little")
    P = ref.scalar_mult(k, (ref.Bx, ref.By))
    return ref.encode_point(P)


@example(scalar=(0).to_bytes(32, "little"))   # 0 * B = identity
@example(scalar=(1).to_bytes(32, "little"))   # 1 * B = B
@example(scalar=(2).to_bytes(32, "little"))   # 2 * B, exercises doubling only
@example(scalar=(3).to_bytes(32, "little"))   # 3 * B, exercises doubling + addition
@given(scalar=scalar_bytes)
@settings(max_examples=300)
def test_scalarmult_base(runner, scalar):
    [out] = runner.run("k_scalarmult_base", [scalar], [32], 1)
    expected = oracle_scalarmult(scalar)
    assert out == expected


def test_scalarmult_identity(runner):
    zero = (0).to_bytes(32, "little")
    [out] = runner.run("k_scalarmult_base", [zero], [32], 1)
    # encoded identity point (0, 1): y=1, x=0 (even) -> sign bit 0
    expected_identity = (1).to_bytes(32, "little")
    assert out == expected_identity
    assert out == oracle_scalarmult(zero)
