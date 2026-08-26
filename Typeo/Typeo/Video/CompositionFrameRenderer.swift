//
//  CompositionFrameRenderer.swift
//  Typeo
//
//  v4. Renders successive frames of ONE persistent scene.
//
//  The still exporter builds a fresh scene per call, which is right for a single frame
//  but wrong for video: physics would restart every frame and a drop would never fall.
//  This holds the scene, the SKRenderer and the Metal objects for the whole recording
//  and just advances the clock.
//
//  Frames are rendered straight into CVPixelBuffer-backed Metal textures so
//  AVAssetWriter can consume them without a CPU copy.
//

import SpriteKit
import Metal
import AVFoundation
import CoreVideo

@MainActor
final class CompositionFrameRenderer {

    let pixelSize: CGSize

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let renderer: SKRenderer
    private let scene: GlyphScene
    private let pool: CVPixelBufferPool
    private let textureCache: CVMetalTextureCache

    init?(composition: Composition, interaction: GlyphInteraction, scale: CGFloat) {
        let reference = composition.aspectRatio.referenceSize
        // H.264 wants even dimensions.
        let width = Int((reference.width * scale / 2).rounded()) * 2
        let height = Int((reference.height * scale / 2).rounded()) * 2
        guard width > 0, height > 0,
              let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue()
        else { return nil }

        var pool: CVPixelBufferPool?
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]
        guard CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool) == kCVReturnSuccess,
              let pool else { return nil }

        var cache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(nil, nil, device, nil, &cache) == kCVReturnSuccess,
              let cache else { return nil }

        self.device = device
        self.queue = queue
        self.pool = pool
        self.textureCache = cache
        self.pixelSize = CGSize(width: width, height: height)

        let scene = GlyphScene(composition: composition, size: reference)
        scene.interaction = interaction
        scene.rebuild()
        scene.beginAutomaticInteraction()
        self.scene = scene

        let renderer = SKRenderer(device: device)
        renderer.scene = scene
        self.renderer = renderer
    }

    /// Advances the scene to `time` and renders one frame.
    func frame(at time: TimeInterval) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
              let buffer else { return nil }

        let width = Int(pixelSize.width)
        let height = Int(pixelSize.height)

        var cvTexture: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(
            nil, textureCache, buffer, nil, .bgra8Unorm, width, height, 0, &cvTexture
        ) == kCVReturnSuccess,
            let cvTexture,
            let target = CVMetalTextureGetTexture(cvTexture)
        else { return nil }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)

        // SKRenderer.update advances the shader clock but does NOT reliably step the
        // scene, so motion is advanced explicitly. Same call the live canvas makes.
        scene.advance(to: time)
        renderer.update(atTime: time)

        guard let commandBuffer = queue.makeCommandBuffer() else { return nil }
        renderer.render(
            withViewport: CGRect(x: 0, y: 0, width: width, height: height),
            commandBuffer: commandBuffer,
            renderPassDescriptor: pass
        )
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        return buffer
    }
}
