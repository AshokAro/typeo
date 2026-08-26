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

    var id: String { name }

    static let all: [StylePreset] = [
        StylePreset(
            name: "Neon",
            font: GlyphFont(fontName: nil, design: .rounded),
            color: RGBAColor(red: 0.55, green: 1, blue: 0.95),
            textGradient: nil,
            background: .solid(RGBAColor(red: 0.03, green: 0.02, blue: 0.08)),
            shader: ShaderEffect(kind: .bloom, intensity: 0.8)
        ),
        StylePreset(
            name: "Chrome",
            font: GlyphFont(fontName: "Futura-Bold", design: .standard),
            color: .white,
            textGradient: nil,
            background: .linearGradient(
                colors: [RGBAColor(red: 0.10, green: 0.11, blue: 0.14),
                         RGBAColor(red: 0.32, green: 0.34, blue: 0.40)],
                angleDegrees: 90
            ),
            shader: ShaderEffect(kind: .chrome, intensity: 0.9, secondary: 0.6)
        ),
        StylePreset(
            name: "Terminal",
            font: GlyphFont(fontName: nil, design: .monospaced),
            color: RGBAColor(red: 0.2, green: 1, blue: 0.4),
            textGradient: nil,
            background: .solid(RGBAColor(red: 0.01, green: 0.03, blue: 0.01)),
            shader: ShaderEffect(kind: .matrix, intensity: 0.75, secondary: 0.5)
        ),
        StylePreset(
            name: "Riso",
            font: GlyphFont(fontName: nil, design: .standard),
            color: RGBAColor(red: 1, green: 0.25, blue: 0.35),
            textGradient: nil,
            background: .solid(RGBAColor(red: 0.96, green: 0.94, blue: 0.86)),
            shader: ShaderEffect(kind: .halftone, intensity: 0.7)
        ),
        StylePreset(
            name: "Vapor",
            font: GlyphFont(fontName: nil, design: .serif),
            color: .white,
            textGradient: .sunset,
            background: .linearGradient(
                colors: [RGBAColor(red: 0.16, green: 0.05, blue: 0.35),
                         RGBAColor(red: 0.02, green: 0.10, blue: 0.28)],
                angleDegrees: 120
            ),
            shader: ShaderEffect(kind: .glass, intensity: 0.6)
        ),
        StylePreset(
            name: "Thermal",
            font: GlyphFont(fontName: nil, design: .rounded),
            color: .white,
            textGradient: nil,
            background: .solid(.black),
            shader: ShaderEffect(kind: .thermal, intensity: 1.0)
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
