//
//  StylePreset.swift
//  Typeo
//
//  One-tap looks. Mostly a discoverability fix: an eleven-shader library is not
//  browsable one slider at a time, but a preset shows what the pieces do together.
//

import SwiftUI

struct StylePreset: Identifiable, Hashable {
    var name: String
    var font: GlyphFont
    var color: RGBAColor
    var textGradient: GradientPaint?
    var background: Background
    var shader: ShaderEffect
    var backgroundShader: ShaderEffect?

    var id: String { name }

    static let all: [StylePreset] = [
        StylePreset(
            name: "Neon",
            font: GlyphFont(fontName: nil, design: .rounded),
            color: .white,
            textGradient: nil,
            background: .solid(RGBAColor(red: 0.02, green: 0.01, blue: 0.06)),
            shader: ShaderEffect(kind: .neon, intensity: 0.85, secondary: 0.15),
            backgroundShader: nil
        ),
        StylePreset(
            name: "Liquid Metal",
            font: GlyphFont(fontName: "Futura-Bold", design: .standard),
            color: .white,
            textGradient: nil,
            background: .solid(RGBAColor(red: 0.06, green: 0.07, blue: 0.09)),
            shader: ShaderEffect(kind: .chrome, intensity: 1.0, secondary: 0.35),
            backgroundShader: nil
        ),
        StylePreset(
            name: "Glass",
            font: GlyphFont(fontName: nil, design: .standard),
            color: .white,
            textGradient: nil,
            background: .linearGradient(
                colors: [RGBAColor(red: 0.10, green: 0.22, blue: 0.45),
                         RGBAColor(red: 0.42, green: 0.16, blue: 0.52)],
                angleDegrees: 120
            ),
            shader: ShaderEffect(kind: .glass, intensity: 0.85),
            backgroundShader: ShaderEffect(kind: .meshGradient, intensity: 0.55, secondary: 0.3)
        ),
        StylePreset(
            name: "Gem Smoke",
            font: GlyphFont(fontName: nil, design: .serif),
            color: .white,
            textGradient: nil,
            background: .solid(RGBAColor(red: 0.04, green: 0.02, blue: 0.10)),
            shader: ShaderEffect(kind: .gemSmoke, intensity: 0.9, secondary: 0.45),
            backgroundShader: ShaderEffect(kind: .grainGradient, intensity: 0.45, secondary: 0.5)
        ),
        StylePreset(
            name: "Heatmap",
            font: GlyphFont(fontName: nil, design: .rounded),
            color: .white,
            textGradient: nil,
            background: .solid(.black),
            shader: ShaderEffect(kind: .thermal, intensity: 1.0),
            backgroundShader: nil
        ),
        StylePreset(
            name: "Dither",
            font: GlyphFont(fontName: nil, design: .monospaced),
            color: RGBAColor(red: 0.95, green: 0.95, blue: 0.9),
            textGradient: nil,
            background: .solid(RGBAColor(red: 0.08, green: 0.10, blue: 0.14)),
            shader: ShaderEffect(kind: .dithering, intensity: 0.9, secondary: 0.25),
            backgroundShader: ShaderEffect(kind: .meshGradient, intensity: 0.8, secondary: 0.7)
        ),
    ]

    /// Small swatch for the picker.
    var previewGradient: LinearGradient {
        if let textGradient { return textGradient.linearGradient }
        return LinearGradient(colors: [color.color, color.color], startPoint: .top, endPoint: .bottom)
    }

    var previewBackground: Color {
        switch background {
        case let .solid(rgba): rgba.color
        case let .linearGradient(colors, _): colors.first?.color ?? .black
        }
    }
}
