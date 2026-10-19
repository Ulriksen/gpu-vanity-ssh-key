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


@pytest.fixture(scope="session")
def table_bytes():
    with open("base_table.bin", "rb") as f:
        data = f.read()
    assert len(data) == 256 * 64
    return data


def oracle_scalarmult(scalar_le_bytes: bytes) -> bytes:
    k = int.from_bytes(scalar_le_bytes, "little")
    P = ref.scalar_mult(k, (ref.Bx, ref.By))
    return ref.encode_point(P)


@example(scalar=(0).to_bytes(32, "little"))
@example(scalar=(1).to_bytes(32, "little"))
@example(scalar=(2).to_bytes(32, "little"))
@example(scalar=(3).to_bytes(32, "little"))
@given(scalar=scalar_bytes)
@settings(max_examples=300)
def test_scalarmult_table_matches_oracle(runner, table_bytes, scalar):
    [out] = runner.run("k_scalarmult_base_table", [scalar, table_bytes], [32], 1)
    assert out == oracle_scalarmult(scalar)


def test_scalarmult_table_matches_double_and_add(runner, table_bytes):
    # the two scalarmult implementations must agree with each other too,
    # not just both happening to match the oracle independently
    import os
    for _ in range(50):
        scalar = os.urandom(32)
        [out_dbl] = runner.run("k_scalarmult_base", [scalar], [32], 1)
        [out_tbl] = runner.run("k_scalarmult_base_table", [scalar, table_bytes], [32], 1)
        assert out_dbl == out_tbl
