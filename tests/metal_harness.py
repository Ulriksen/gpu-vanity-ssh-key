import Metal


class MetalRunner:
    def __init__(self, source_path):
        with open(source_path) as f:
            source = f.read()
        self.device = Metal.MTLCreateSystemDefaultDevice()
        assert self.device is not None, "no Metal device found"
        library, error = self.device.newLibraryWithSource_options_error_(source, None, None)
        assert library is not None, f"compile error: {error}"
        self.library = library
        self.queue = self.device.newCommandQueue()
        self._pipelines = {}

    def _pipeline(self, name):
        if name not in self._pipelines:
            fn = self.library.newFunctionWithName_(name)
            assert fn is not None, f"no such kernel: {name}"
            pipeline, error = self.device.newComputePipelineStateWithFunction_error_(fn, None)
            assert pipeline is not None, f"pipeline error: {error}"
            self._pipelines[name] = pipeline
        return self._pipelines[name]

    def run(self, kernel_name, input_buffers, output_sizes, n_threads):
        pipeline = self._pipeline(kernel_name)
        cmd = self.queue.commandBuffer()
        enc = cmd.computeCommandEncoder()
        enc.setComputePipelineState_(pipeline)

        idx = 0
        for data in input_buffers:
            buf = self.device.newBufferWithBytes_length_options_(
                data, len(data), Metal.MTLResourceStorageModeShared
            )
            enc.setBuffer_offset_atIndex_(buf, 0, idx)
            idx += 1

        out_buffers = []
        for size in output_sizes:
            buf = self.device.newBufferWithLength_options_(
                size, Metal.MTLResourceStorageModeShared
            )
            enc.setBuffer_offset_atIndex_(buf, 0, idx)
            out_buffers.append(buf)
            idx += 1

        grid = Metal.MTLSizeMake(n_threads, 1, 1)
        tg_size = min(n_threads, pipeline.maxTotalThreadsPerThreadgroup())
        tg = Metal.MTLSizeMake(tg_size, 1, 1)
        enc.dispatchThreads_threadsPerThreadgroup_(grid, tg)
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()

        return [bytes(buf.contents().as_buffer(size)) for buf, size in zip(out_buffers, output_sizes)]
