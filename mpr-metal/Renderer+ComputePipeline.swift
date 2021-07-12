import Metal

extension Renderer {
    class func makeTapeBuffer(device: MTLDevice) -> MTLBuffer? {
        let tapeBuffer = device.makeBuffer(length: 32000000)
        MPR.fillBuffer(tapeBuffer?.contents())
        return tapeBuffer
    }

    class func makeTileBuffer(imageSize: Int, tileSize: Int, device: MTLDevice) -> MTLBuffer? {
        let tilesPerSide = imageSize / tileSize
        let arraySize = tilesPerSide * tilesPerSide * MemoryLayout<UInt32>.stride
        return device.makeBuffer(length: arraySize, options: .storageModeShared)
    }

    class func makeComputePSO(_ functionName: String, library: MTLLibrary, device: MTLDevice) throws -> MTLComputePipelineState {
        guard let computeFunction = library.makeFunction(name: functionName) else {
            throw RendererError.unknownComputeFunction
        }
        return try device.makeComputePipelineState(function: computeFunction)
    }
}
