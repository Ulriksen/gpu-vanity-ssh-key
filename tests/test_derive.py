import os
import pytest
from hypothesis import given, settings, example, strategies as st
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives import serialization
from metal_harness import MetalRunner

settings.register_profile("gpu", deadline=None)
settings.load_profile("gpu")

seed32 = st.binary(min_size=32, max_size=32)


@pytest.fixture(scope="session")
def runner():
    return MetalRunner("fe25519.metal")


@pytest.fixture(scope="session")
def table_bytes():
    with open("base_table.bin", "rb") as f:
        data = f.read()
    assert len(data) == 256 * 64
    return data


def expected_pubkey(seed: bytes) -> bytes:
    priv = Ed25519PrivateKey.from_private_bytes(seed)
    return priv.public_key().public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw,
    )


@example(seed=bytes(32))
@example(seed=bytes([0xff] * 32))
@given(seed=seed32)
@settings(max_examples=2000)
def test_derive_pubkey_matches_cryptography(runner, table_bytes, seed):
    [out] = runner.run("k_derive_pubkey", [seed, table_bytes], [32], 1)
    assert out == expected_pubkey(seed)


def test_derive_pubkey_batch_of_random_os_seeds(runner, table_bytes):
    # also exercise a real batch dispatch (N threads at once), not just N=1
    seeds = [os.urandom(32) for _ in range(512)]
    blob = b"".join(seeds)
    [out] = runner.run("k_derive_pubkey", [blob, table_bytes], [32 * 512], 512)
    for i, seed in enumerate(seeds):
        got = out[i*32:(i+1)*32]
        assert got == expected_pubkey(seed), f"mismatch at index {i}"
