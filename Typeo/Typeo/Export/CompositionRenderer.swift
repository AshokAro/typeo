//
//  CompositionRenderer.swift
//  Typeo
//
//  The single render path. The editor preview and the export both call this, so an
//  effect can never look one way on screen and another in the saved file.
//

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

@MainActor
enum CompositionRenderer {

    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Renders the canvas and applies the composition's effect.
    /// - Parameter scale: 1 gives reference-size pixels (1080 wide), 2 gives 2160.
    static func render(_ composition: Composition, scale: CGFloat = 2) -> UIImage? {
        let renderer = ImageRenderer(content: CompositionCanvas(composition: composition))
        renderer.scale = scale
        renderer.isOpaque = true
        guard let base = renderer.uiImage else { return nil }
        return apply(composition.globalShader, to: base)
    }

    static func apply(_ effect: ShaderEffect, to image: UIImage) -> UIImage {
        guard effect.kind != .none, effect.intensity > 0.001, let cgImage = image.cgImage else {
            return image
        }

        let input = CIImage(cgImage: cgImage)
        let output: CIImage?

        switch effect.kind {
        case .none:
            output = nil
        case .bloom:
            let filter = CIFilter.bloom()
            filter.inputImage = input
            filter.intensity = Float(effect.intensity * 1.4)
            filter.radius = Float(8 + effect.intensity * 55)
            output = filter.outputImage
        }

        guard let cropped = output?.cropped(to: input.extent),
              let rendered = context.createCGImage(cropped, from: input.extent) else {
            return image
        }
        return UIImage(cgImage: rendered, scale: image.scale, orientation: .up)
    }
}
