//
//  CompositionCanvas.swift
//  Typeo
//
//  THE EXPORTABLE VIEW. Content only — never chrome, never Liquid Glass.
//  The editor scales this down for display; the exporter renders this exact view
//  at the same logical size. Both paths run the same code, so WYSIWYG is structural.
//

import SwiftUI

struct BackgroundView: View {
    let background: Background

    var body: some View {
        switch background {
        case let .solid(rgba):
            rgba.color
        case let .linearGradient(colors, angleDegrees):
            LinearGradient(
                colors: colors.map(\.color),
                startPoint: UnitPoint(
                    x: 0.5 - 0.5 * cos(angleDegrees * .pi / 180),
                    y: 0.5 - 0.5 * sin(angleDegrees * .pi / 180)
                ),
                endPoint: UnitPoint(
                    x: 0.5 + 0.5 * cos(angleDegrees * .pi / 180),
                    y: 0.5 + 0.5 * sin(angleDegrees * .pi / 180)
                )
            )
        }
    }
}

struct GlyphView: View {
    let glyph: Glyph

    var body: some View {
        Text(verbatim: glyph.character)
            .font(glyph.font.font(size: glyph.size))
            .foregroundStyle(glyph.color.color)
            .fixedSize()
            .rotationEffect(.degrees(glyph.rotation))
            .offset(x: glyph.positionOffset.x, y: glyph.positionOffset.y)
            .layoutValue(key: GlyphRoleKey.self, value: glyph.role)
    }
}

struct CompositionCanvas: View {
    let composition: Composition
    /// Seconds on the editor's animation clock. Animated shaders read this; static
    /// ones ignore it. Export passes the clock value at the moment of export.
    var time: Double = 0

    /// Fraction of canvas width the text block may occupy.
    private let textInset: CGFloat = 0.88

    var body: some View {
        let reference = composition.aspectRatio.referenceSize
        let dominant = composition.dominantSize
        let bleed = composition.globalShader.kind.sampleOffset

        ZStack {
            BackgroundView(background: composition.background)

            GlyphFlowLayout(
                lineSpacing: dominant * 0.14,
                fallbackLineHeight: dominant * 0.9
            ) {
                ForEach(composition.glyphs) { glyph in
                    GlyphView(glyph: glyph)
                }
            }
            .frame(maxWidth: reference.width * textInset)
            // Bleed room so a glow or a tear is not clipped at the block's edge.
            .padding(bleed)
            .modifier(TextBlockShader(effect: composition.globalShader, time: time))
        }
        .frame(width: reference.width, height: reference.height)
        .clipped()
    }
}

#Preview {
    let store = CompositionStore()
    store.setText("Typeo")
    return CompositionCanvas(composition: store.composition)
        .scaleEffect(0.3)
        .frame(width: 324, height: 324)
}
