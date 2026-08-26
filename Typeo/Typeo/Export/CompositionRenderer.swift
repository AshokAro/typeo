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
    static func render(_ composition: Composition, time: Double = 0, scale: CGFloat = 2) -> UIImage? {
        SpriteCompositionRenderer.render(composition, time: time, scale: scale)
    }
}
