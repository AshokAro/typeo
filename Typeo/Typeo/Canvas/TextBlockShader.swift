//
//  TextBlockShader.swift
//  Typeo
//
//  Maps a ShaderEffect onto the SwiftUI shader modifier it needs. Applied to the
//  TEXT BLOCK only — not the background, not the chrome (CLAUDE.md).
//
//  ImageRenderer captures colorEffect, distortionEffect and layerEffect output, so
//  the live canvas and the exported file run this exact modifier. Verified, not assumed.
//

import SwiftUI

struct TextBlockShader: ViewModifier {
    let effect: ShaderEffect
    /// Seconds since the editor's animation clock started. Frozen at export.
    let time: Double

    @ViewBuilder
    func body(content: Content) -> some View {
        switch effect.kind {
        case .none:
            content

        case .bloom:
            content.layerEffect(
                ShaderLibrary.bloom(.float(effect.intensity)),
                maxSampleOffset: offset
            )

        case .heat:
            content.distortionEffect(
                ShaderLibrary.heat(.float(time), .float(effect.intensity)),
                maxSampleOffset: offset
            )

        case .noise:
            content.colorEffect(
                ShaderLibrary.grain(.float(time), .float(effect.intensity))
            )

        case .glitch:
            content.layerEffect(
                ShaderLibrary.glitch(.float(time), .float(effect.intensity)),
                maxSampleOffset: offset
            )
        }
    }

    private var offset: CGSize {
        let value = effect.kind.sampleOffset
        return CGSize(width: value, height: value)
    }
}
