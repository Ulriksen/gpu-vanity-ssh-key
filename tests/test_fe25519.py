import pytest
from hypothesis import given, settings, example, strategies as st
settings.register_profile("gpu", deadline=None)
settings.load_profile("gpu")
from metal_harness import MetalRunner

P = 2**255 - 19
fe_bytes = st.binary(min_size=32, max_size=32)


def fe_int(b: bytes) -> int:
    v = int.from_bytes(b, "little")
    v &= (1 << 255) - 1  # frombytes ignores the top bit
    return v % P


@pytest.fixture(scope="session")
def runner():
    return MetalRunner("fe25519.metal")


@example(a=(0).to_bytes(32, "little"))
@example(a=(1).to_bytes(32, "little"))
@example(a=(P).to_bytes(32, "little"))                 # exactly p -> reduces to 0
@example(a=((1 << 255) - 1).to_bytes(32, "little"))     # p + 18 -> reduces to 18
@example(a=bytes(31) + bytes([0x80]))                   # only the ignored top bit set -> 0
@given(a=fe_bytes)
@settings(max_examples=500)
def test_roundtrip(runner, a):
    [out] = runner.run("k_fe_roundtrip", [a], [32], 1)
    assert int.from_bytes(out, "little") == fe_int(a)


@given(a=fe_bytes, b=fe_bytes)
@settings(max_examples=1000)
def test_add(runner, a, b):
    [out] = runner.run("k_fe_add", [a, b], [32], 1)
    assert int.from_bytes(out, "little") == (fe_int(a) + fe_int(b)) % P


@given(a=fe_bytes, b=fe_bytes)
@settings(max_examples=1000)
def test_sub(runner, a, b):
    [out] = runner.run("k_fe_sub", [a, b], [32], 1)
    assert int.from_bytes(out, "little") == (fe_int(a) - fe_int(b)) % P


@given(a=fe_bytes, b=fe_bytes)
@settings(max_examples=1000)
def test_mul(runner, a, b):
    [out] = runner.run("k_fe_mul", [a, b], [32], 1)
    assert int.from_bytes(out, "little") == (fe_int(a) * fe_int(b)) % P


@given(a=fe_bytes)
@settings(max_examples=500)
def test_sq(runner, a):
    [out] = runner.run("k_fe_sq", [a], [32], 1)
    assert int.from_bytes(out, "little") == (fe_int(a) * fe_int(a)) % P


@given(a=fe_bytes)
@settings(max_examples=300)
def test_invert(runner, a):
    av = fe_int(a)
    if av == 0:
        return
    [out] = runner.run("k_fe_invert", [a], [32], 1)
    assert int.from_bytes(out, "little") == pow(av, P - 2, P)


def test_invert_zero(runner):
    zero = (0).to_bytes(32, "little")
    [out] = runner.run("k_fe_invert", [zero], [32], 1)
    assert int.from_bytes(out, "little") == 0


@given(a=fe_bytes, b=fe_bytes, c=fe_bytes)
@settings(max_examples=300)
def test_mul_distributes_over_add(runner, a, b, c):
    [bc] = runner.run("k_fe_add", [b, c], [32], 1)
    [a_bc] = runner.run("k_fe_mul", [a, bc], [32], 1)
    [ab] = runner.run("k_fe_mul", [a, b], [32], 1)
    [ac] = runner.run("k_fe_mul", [a, c], [32], 1)
    [ab_ac] = runner.run("k_fe_add", [ab, ac], [32], 1)
    assert fe_int(a_bc) == fe_int(ab_ac)


@given(a=fe_bytes)
@settings(max_examples=300)
def test_mul_inverse_is_one(runner, a):
    av = fe_int(a)
    if av == 0:
        return
    [inv] = runner.run("k_fe_invert", [a], [32], 1)
    [prod] = runner.run("k_fe_mul", [a, inv], [32], 1)
    assert fe_int(prod) == 1
