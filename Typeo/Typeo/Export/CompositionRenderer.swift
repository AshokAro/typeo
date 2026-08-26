//
//  CompositionRenderer.swift
//  Typeo
//
//  Single entry point for turning a Composition into an image. v3 moved the
//  implementation to SpriteKit; callers (export, gallery thumbnails) did not change.
//
//  v4 note: frame-by-frame video export is this call in a loop over `time`.
//

import UIKit

@MainActor
enum CompositionRenderer {
    /// - Parameter tilt: the device lean the canvas is currently showing. Passed in so
    ///   an export carries the background parallax and the swung light that were on
    ///   screen — rendering at zero would quietly differ from the preview.
    static func render(
        _ composition: Composition,
        time: Double = 0,
        scale: CGFloat = 2,
        tilt: CGVector = .zero
    ) -> UIImage? {
        SpriteCompositionRenderer.render(composition, time: time, scale: scale, tilt: tilt)
    }
}
