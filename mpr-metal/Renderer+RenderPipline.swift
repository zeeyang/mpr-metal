import Metal
import MetalKit

extension Renderer {
    class func makeVertexBuffer(device: MTLDevice) -> MTLBuffer? {
        let vertexData: [Float] = [-1.0, -1.0, 0.0, 1.0,
                                   1.0, -1.0, 0.0, 1.0,
                                   -1.0, 1.0, 0.0, 1.0,
                                   -1.0, 1.0, 0.0, 1.0,
                                   1.0, -1.0, 0.0, 1.0,
                                   1.0,  1.0, 0.0, 1.0]
        let dataSize = vertexData.count * MemoryLayout<Float>.stride
        return device.makeBuffer(bytes: vertexData, length: dataSize)
    }

    class func makeUniformBuffer(device: MTLDevice) -> MTLBuffer? {
        let size = MemoryLayout<Uniforms>.stride
        return device.makeBuffer(length: size, options: .storageModeShared)
    }

    class func makeAtomicBuffer(device: MTLDevice) -> MTLBuffer? {
        let size = MemoryLayout<Atomics>.stride
        return device.makeBuffer(length: size, options: .storageModeShared)
    }

    class func makeTexture(width: Int, height: Int, device: MTLDevice) -> MTLTexture {
        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.storageMode = .managed
        textureDescriptor.usage = [.shaderWrite, .shaderRead]
        textureDescriptor.pixelFormat = .r8Uint
        textureDescriptor.width = width
        textureDescriptor.height = height
        textureDescriptor.depth = 1

        let texture = device.makeTexture(descriptor: textureDescriptor)!
        let seed = [UInt8](repeating: 0, count: width * height)
        // TODO: blit?
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: seed,
            bytesPerRow: width * MemoryLayout<UInt8>.stride
        )
        return texture
    }

    class func makeRenderPSO(library: MTLLibrary, device: MTLDevice, metalKitView: MTKView) throws -> MTLRenderPipelineState {
        let vertexFunction = library.makeFunction(name: "vertexShader")
        let fragmentFunction = library.makeFunction(name: "fragmentShader")

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "RenderPipeline"
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction

        pipelineDescriptor.colorAttachments[0].pixelFormat = metalKitView.colorPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = metalKitView.depthStencilPixelFormat
        pipelineDescriptor.stencilAttachmentPixelFormat = metalKitView.depthStencilPixelFormat

        return try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }
}
