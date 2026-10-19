import base64
import struct
import os
import pytest
import Metal
from hypothesis import given, settings, strategies as st
from metal_harness import MetalRunner

settings.register_profile("gpu", deadline=None)
settings.load_profile("gpu")

MAX_TARGET_LEN = 32


@pytest.fixture(scope="session")
def runner():
    return MetalRunner("fe25519.metal")


@pytest.fixture(scope="session")
def table_bytes():
    with open("base_table.bin", "rb") as f:
        data = f.read()
    assert len(data) == 256 * 64
    return data


@given(data=st.binary(min_size=51, max_size=51))
@settings(max_examples=500)
def test_base64_51(runner, data):
    [out] = runner.run("k_base64_51", [data], [68], 1)
    assert out.decode("ascii") == base64.b64encode(data).decode("ascii")


def wire_b64(pub: bytes) -> str:
    prefix = struct.pack(">I", 11) + b"ssh-ed25519" + struct.pack(">I", 32)
    return base64.b64encode(prefix + pub).decode()


def run_grind(runner, table_bytes, seeds, targets):
    assert all(1 <= len(t) <= MAX_TARGET_LEN for t in targets)
    targets_buf = b"".join(t.encode().ljust(MAX_TARGET_LEN, b"\x00") for t in targets)
    lens_buf = b"".join(struct.pack("I", len(t)) for t in targets)
    max_matches = 64

    pipeline = runner._pipeline("k_grind")
    device = runner.device
    cmd = runner.queue.commandBuffer()
    enc = cmd.computeCommandEncoder()
    enc.setComputePipelineState_(pipeline)

    b_seeds = device.newBufferWithBytes_length_options_(b"".join(seeds), 32 * len(seeds), Metal.MTLResourceStorageModeShared)
    b_table = device.newBufferWithBytes_length_options_(table_bytes, len(table_bytes), Metal.MTLResourceStorageModeShared)
    b_targets = device.newBufferWithBytes_length_options_(targets_buf, len(targets_buf), Metal.MTLResourceStorageModeShared)
    b_lens = device.newBufferWithBytes_length_options_(lens_buf, len(lens_buf), Metal.MTLResourceStorageModeShared)
    b_numt = device.newBufferWithBytes_length_options_(struct.pack("I", len(targets)), 4, Metal.MTLResourceStorageModeShared)
    b_count = device.newBufferWithBytes_length_options_(struct.pack("I", 0), 4, Metal.MTLResourceStorageModeShared)
    b_matches = device.newBufferWithBytes_length_options_(bytes(32 * max_matches), 32 * max_matches, Metal.MTLResourceStorageModeShared)
    b_maxm = device.newBufferWithBytes_length_options_(struct.pack("I", max_matches), 4, Metal.MTLResourceStorageModeShared)

    for i, b in enumerate([b_seeds, b_table, b_targets, b_lens, b_numt, b_count, b_matches, b_maxm]):
        enc.setBuffer_offset_atIndex_(b, 0, i)

    n = len(seeds)
    grid = Metal.MTLSizeMake(n, 1, 1)
    tg = Metal.MTLSizeMake(min(n, pipeline.maxTotalThreadsPerThreadgroup()), 1, 1)
    enc.dispatchThreads_threadsPerThreadgroup_(grid, tg)
    enc.endEncoding()
    cmd.commit()
    cmd.waitUntilCompleted()

    count = struct.unpack("I", bytes(b_count.contents().as_buffer(4)))[0]
    raw = bytes(b_matches.contents().as_buffer(32 * max_matches))
    matched = [raw[i*32:(i+1)*32] for i in range(min(count, max_matches))]
    return count, matched


def derive_batch_pubkeys(runner, table_bytes, seeds):
    blob = b"".join(seeds)
    [out] = runner.run("k_derive_pubkey", [blob, table_bytes], [32 * len(seeds)], len(seeds))
    return [out[i*32:(i+1)*32] for i in range(len(seeds))]


def test_grind_finds_exactly_the_real_matches(runner, table_bytes):
    # No brute force: derive a batch for real via the (already-proven) GPU
    # derivation kernel, read off two of its *actual* 7-char suffixes, then
    # confirm k_grind flags exactly those two seeds and no others.
    seeds = [os.urandom(32) for _ in range(2000)]
    pubs = derive_batch_pubkeys(runner, table_bytes, seeds)
    suffixes = [wire_b64(p)[-7:] for p in pubs]

    i1, i2 = 17, 1583
    targets = [suffixes[i1], suffixes[i2]]
    assert targets[0] != targets[1], "pick different indices if this ever collides"

    count, matched = run_grind(runner, table_bytes, seeds, targets)

    expected_indices = {idx for idx, s in enumerate(suffixes) if s in targets}
    assert count == len(expected_indices)
    assert set(matched) == {seeds[idx] for idx in expected_indices}
    assert i1 in expected_indices and i2 in expected_indices


def test_grind_mixed_length_targets_in_one_run(runner, table_bytes):
    # The whole point of variable-length support: a short target and a long
    # target searched for simultaneously in the same dispatch. Again, no
    # brute force -- read real suffixes of different lengths off a real
    # derived batch.
    seeds = [os.urandom(32) for _ in range(2000)]
    pubs = derive_batch_pubkeys(runner, table_bytes, seeds)
    full = [wire_b64(p) for p in pubs]

    i_short, i_long = 42, 999
    short_target = full[i_short][-3:]   # 3 chars
    long_target = full[i_long][-15:]    # 15 chars
    targets = [short_target, long_target]

    count, matched = run_grind(runner, table_bytes, seeds, targets)

    expected_indices = {idx for idx, s in enumerate(full) if s.endswith(short_target) or s.endswith(long_target)}
    assert count == len(expected_indices)
    assert set(matched) == {seeds[idx] for idx in expected_indices}
    assert i_short in expected_indices and i_long in expected_indices


def test_grind_no_false_positives_on_plain_batch(runner, table_bytes):
    targets = ["/harald", "/Harald", "+harald", "+Harald"]
    seeds = [os.urandom(32) for _ in range(5000)]
    count, matched = run_grind(runner, table_bytes, seeds, targets)
    # astronomically unlikely to hit a real match in 5000 tries; this is
    # really checking the kernel doesn't spuriously flag things it shouldn't.
    assert count == 0
