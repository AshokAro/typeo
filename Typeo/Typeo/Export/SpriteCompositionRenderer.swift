//
//  SpriteCompositionRenderer.swift
//  Typeo
//
//  v3 export path. ImageRenderer cannot capture SpriteView — it renders SwiftUI's
//  "unsupported view" placeholder — so export goes through SKRenderer into an
//  offscreen Metal texture.
//
//  SKView.texture(from:) was the obvious alternative but its output size is pinned to
//  the screen's scale (3240px on a 3x device) and ignores contentScaleFactor, which
//  would make export resolution depend on the device. SKRenderer gives an exact size.
//

import SpriteKit
import Metal
import UIKit

@MainActor
enum SpriteCompositionRenderer {

    private static let device = MTLCreateSystemDefaultDevice()
    private static var queue: MTLCommandQueue?

    /// - Parameters:
    ///   - time: scene time, so animated shaders can be frozen at a chosen frame.
    ///   - scale: 1 renders at reference size (1080 wide), 2 at 2160.
    static func render(_ composition: Composition, time: Double = 0, scale: CGFloat = 2) -> UIImage? {
        let reference = composition.aspectRatio.referenceSize
        let width = Int(reference.width * scale)
        let height = Int(reference.height * scale)

        guard let device, width > 0, height > 0 else { return nil }
        if queue == nil { queue = device.makeCommandQueue() }
        guard let queue else { return nil }

        let scene = GlyphScene(composition: composition, size: reference)
        scene.rebuild()

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let target = device.makeTexture(descriptor: descriptor) else { return nil }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)

        let renderer = SKRenderer(device: device)
        renderer.scene = scene
        renderer.update(atTime: time)

        guard let buffer = queue.makeCommandBuffer() else { return nil }
        renderer.render(
            withViewport: CGRect(x: 0, y: 0, width: width, height: height),
            commandBuffer: buffer,
            renderPassDescriptor: pass
        )
        buffer.commit()
        buffer.waitUntilCompleted()

        let rowBytes = width * 4
        var raw = [UInt8](repeating: 0, count: rowBytes * height)
        target.getBytes(&raw, bytesPerRow: rowBytes,
                        from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)

        guard let provider = CGDataProvider(data: Data(raw) as CFData),
              let cgImage = CGImage(
                width: width, height: height,
                bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: rowBytes,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(
                    rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                        | CGBitmapInfo.byteOrder32Little.rawValue
                ),
                provider: provider, decode: nil,
                shouldInterpolate: false, intent: .defaultIntent
              )
        else { return nil }

        return UIImage(cgImage: cgImage)
    }
}
