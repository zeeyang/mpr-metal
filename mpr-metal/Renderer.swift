import Metal
import MetalKit

let maxBuffersInFlight = 1

enum RendererError: Error {
    case badVertexDescriptor
    case unknownComputeFunction
}

final class Renderer: NSObject {

    public let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let inFlightSemaphore = DispatchSemaphore(value: maxBuffersInFlight)
    let imageSize = 1024
    let tileSize0 = 64
    let tileSize1 = 8

    var tilesPerSide0: Int {
        return imageSize / tileSize0
    }
    var tilesPerSide1: Int {
        return imageSize / tileSize1
    }

    let vertexBuffer: MTLBuffer
    let tapeBuffer: MTLBuffer

    let tileBuffer0: MTLBuffer
    var tileBuffer1: MTLBuffer?

    let uniformBuffer: MTLBuffer
    let atomicBuffer: MTLBuffer

    let image: MTLTexture

    let renderPSO: MTLRenderPipelineState

    let clearTilesPSO: MTLComputePipelineState
    let evalTiles2DPSO: MTLComputePipelineState
    let debugTiles2DPSO: MTLComputePipelineState
    let subdivideTiles2DPSO: MTLComputePipelineState
    let evalPixelsPSO: MTLComputePipelineState

    var uniforms: UnsafeMutablePointer<Uniforms>
    var atomics: UnsafeMutablePointer<Atomics>

    var projectionMatrix: matrix_float4x4 = matrix_identity_float4x4

    init?(metalKitView: MTKView) {
        self.device = metalKitView.device!
        self.commandQueue = self.device.makeCommandQueue()!

        vertexBuffer = Renderer.makeVertexBuffer(device: device)!

        guard let library = device.makeDefaultLibrary() else {
            return nil
        }
        do {
            renderPSO = try Renderer.makeRenderPSO(library: library, device: device, metalKitView: metalKitView)
            clearTilesPSO = try Renderer.makeComputePSO("clear_tiles_2d", library: library, device: device)
            evalTiles2DPSO = try Renderer.makeComputePSO("eval_tiles_2d", library: library, device: device)
            debugTiles2DPSO = try Renderer.makeComputePSO("debug_tiles_2d", library: library, device: device)
            subdivideTiles2DPSO = try Renderer.makeComputePSO("subdivide_tiles_2d", library: library, device: device)
            evalPixelsPSO = try Renderer.makeComputePSO("eval_pixels", library: library, device: device)
        } catch {
            print("Unable to compile pipeline state.  Error info: \(error)")
            return nil
        }

        tapeBuffer = Renderer.makeTapeBuffer(device: device)!
        tileBuffer0 = Renderer.makeTileBuffer(imageSize: imageSize, tileSize: tileSize0, device: device)!
        tileBuffer1 = Renderer.makeTileBuffer(imageSize: imageSize, tileSize: tileSize1, device: device)!

        uniformBuffer = Renderer.makeUniformBuffer(device: device)!
        uniforms = UnsafeMutableRawPointer(uniformBuffer.contents()).bindMemory(to:Uniforms.self, capacity:1)
        uniforms[0].projectionMatrix = projectionMatrix

        atomicBuffer = Renderer.makeAtomicBuffer(device: device)!
        atomics = UnsafeMutableRawPointer(atomicBuffer.contents()).bindMemory(to:Atomics.self, capacity:1)

        image = Renderer.makeTexture(width: imageSize, height: imageSize, device: device)

        super.init()
    }
}

extension Renderer: MTKViewDelegate {
    func draw(in view: MTKView) {
        _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        commandBuffer.addCompletedHandler { (_ commandBuffer)-> Swift.Void in
            self.atomics[0].tapeIndex = 0
            self.inFlightSemaphore.signal()
        }

        guard let desc = view.currentRenderPassDescriptor,
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: desc) else {
            return
        }

        renderEncoder.setRenderPipelineState(renderPSO)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.setFragmentTexture(image, index: 0)
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        renderEncoder.endEncoding()

        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }

        computeEncoder.setBuffer(tapeBuffer, offset: 0, index: Int(BufferIndex.tape.rawValue))
        computeEncoder.setBuffer(tileBuffer0, offset: 0, index: Int(BufferIndex.tiles.rawValue))
        computeEncoder.setBuffer(tileBuffer1, offset: 0, index: Int(BufferIndex.nextTiles.rawValue))
        computeEncoder.setBuffer(uniformBuffer, offset: 0, index: Int(BufferIndex.uniforms.rawValue))
        computeEncoder.setBuffer(atomicBuffer, offset: 0, index: Int(BufferIndex.atomics.rawValue))

        dispatchThreads(grid: tilesPerSide0, width: 8, pipeline: clearTilesPSO, encoder: computeEncoder)
        dispatchThreads(grid: tilesPerSide0, width: 8, pipeline: evalTiles2DPSO, encoder: computeEncoder)
        dispatchThreads(grid: tilesPerSide1, width: 64, pipeline: subdivideTiles2DPSO, encoder: computeEncoder)

        computeEncoder.setBuffer(tileBuffer1, offset: 0, index: Int(BufferIndex.tiles.rawValue))
        dispatchThreads(grid: tilesPerSide1, width: 64, pipeline: evalTiles2DPSO, encoder: computeEncoder)

        computeEncoder.setTexture(image, index: Int(TextureIndex.tiles.rawValue))
        dispatchThreads(grid: (tilesPerSide1 * 8, tilesPerSide1 * 4), width: 64, pipeline: evalPixelsPSO, encoder: computeEncoder)

        computeEncoder.endEncoding()

        if let drawable = view.currentDrawable {
            commandBuffer.present(drawable)
        }
        commandBuffer.commit()
    }

    func dispatchThreads(grid: (Int, Int), width: Int, pipeline: MTLComputePipelineState, encoder: MTLComputeCommandEncoder) {
        let gridSize = MTLSize(width: grid.0, height: grid.1, depth: 1)
        let maxThreads = pipeline.maxTotalThreadsPerThreadgroup
        let threadGroupSize = MTLSize(width: width, height: maxThreads/width, depth: 1)
        encoder.setComputePipelineState(pipeline)
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadGroupSize)
    }

    func dispatchThreads(grid: Int, width: Int, pipeline: MTLComputePipelineState, encoder: MTLComputeCommandEncoder) {
        dispatchThreads(grid: (grid, grid), width: width, pipeline: pipeline, encoder: encoder)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
//        /// Respond to drawable size or orientation changes here
//
//        let aspect = Float(size.width) / Float(size.height)
//        projectionMatrix = matrix_perspective_right_hand(fovyRadians: radians_from_degrees(65), aspectRatio:aspect, nearZ: 0.1, farZ: 100.0)
    }
}
