//
//  CompositionRenderer.swift
//  Typeo
//
//  The single render path. The editor preview and the export render the SAME view
//  with the SAME modifiers, so an effect cannot look one way on screen and another
//  in the saved file. Verified: ImageRenderer captures colorEffect, distortionEffect
//  and layerEffect output.
//
//  v4 note: frame-by-frame video export is this function called in a loop over `time`.
//

import SwiftUI
import UIKit

@MainActor
enum CompositionRenderer {

    /// - Parameters:
    ///   - time: animation-clock value to freeze the shader at.
    ///   - scale: 1 gives reference-size pixels (1080 wide), 2 gives 2160.
    static func render(_ composition: Composition, time: Double = 0, scale: CGFloat = 2) -> UIImage? {
        let renderer = ImageRenderer(
            content: CompositionCanvas(composition: composition, time: time)
        )
        renderer.scale = scale
        renderer.isOpaque = true
        return renderer.uiImage
    }
}
