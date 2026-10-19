import struct
import Metal
import Foundation


def run_kernel(source, func_name, input_values):
    device = Metal.MTLCreateSystemDefaultDevice()
    assert device is not None, "no Metal device found"

    library, error = device.newLibraryWithSource_options_error_(source, None, None)
    assert library is not None, f"compile error: {error}"

    function = library.newFunctionWithName_(func_name)
    assert function is not None, f"function {func_name} not found"

    pipeline, error = device.newComputePipelineStateWithFunction_error_(function, None)
    assert pipeline is not None, f"pipeline error: {error}"

    n = len(input_values)
    in_bytes = struct.pack(f"{n}I", *input_values)
    buf_in = device.newBufferWithBytes_length_options_(
        in_bytes, len(in_bytes), Metal.MTLResourceStorageModeShared
    )
    buf_out = device.newBufferWithLength_options_(
        len(in_bytes), Metal.MTLResourceStorageModeShared
    )

    queue = device.newCommandQueue()
    cmd = queue.commandBuffer()
    enc = cmd.computeCommandEncoder()
    enc.setComputePipelineState_(pipeline)
    enc.setBuffer_offset_atIndex_(buf_in, 0, 0)
    enc.setBuffer_offset_atIndex_(buf_out, 0, 1)

    grid = Metal.MTLSizeMake(n, 1, 1)
    tg = Metal.MTLSizeMake(min(n, pipeline.maxTotalThreadsPerThreadgroup()), 1, 1)
    enc.dispatchThreads_threadsPerThreadgroup_(grid, tg)
    enc.endEncoding()
    cmd.commit()
    cmd.waitUntilCompleted()

    out_ptr = buf_out.contents()
    out_bytes = out_ptr.as_buffer(len(in_bytes))
    return list(struct.unpack(f"{n}I", out_bytes))


DOUBLE_KERNEL = """
#include <metal_stdlib>
using namespace metal;

kernel void double_it(device const uint* in [[buffer(0)]],
                       device uint* out [[buffer(1)]],
                       uint id [[thread_position_in_grid]]) {
    out[id] = in[id] * 2;
}
"""


def test_plumbing_double():
    inputs = [0, 1, 2, 3, 100, 65535, 12345]
    outputs = run_kernel(DOUBLE_KERNEL, "double_it", inputs)
    assert outputs == [x * 2 for x in inputs]
