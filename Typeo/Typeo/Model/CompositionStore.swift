//
//  CompositionStore.swift
//  Typeo
//
//  v1's entire job: write the SAME value to EVERY glyph.
//  Every mutation below funnels through `mutateAllGlyphs`. When v3 adds per-letter
//  mode it writes to individual glyphs instead — the model and this store both stay.
//

import SwiftUI
import Observation

/// The one style v1's UI edits. v3 stops using this as the single source and starts
/// reading each glyph's own values.
struct GlyphStyle: Codable, Hashable {
    var font: GlyphFont = .system
    var size: CGFloat = 150
    var color: RGBAColor = .white
}

@Observable
final class CompositionStore {
    var composition: Composition
    /// The values v1 broadcasts to every glyph, and applies to newly typed ones.
    var style: GlyphStyle

    init(composition: Composition = Composition(), style: GlyphStyle = GlyphStyle()) {
        self.composition = composition
        self.style = style
    }

    // MARK: Text

    var text: String {
        get { composition.text }
        set { setText(newValue) }
    }

    /// Reconciles typed text against existing glyphs positionally, so a glyph keeps its
    /// identity and attributes when surrounding text changes. In v1 every glyph shares
    /// one style so this is invisible — in v3 it is what stops editing from wiping
    /// per-letter work.
    func setText(_ newText: String) {
        let characters = Array(newText)
        var next: [Glyph] = []
        next.reserveCapacity(characters.count)

        for (index, character) in characters.enumerated() {
            if index < composition.glyphs.count {
                var existing = composition.glyphs[index]
                existing.character = String(character)
                next.append(existing)
            } else {
                next.append(
                    Glyph(
                        character: String(character),
                        font: style.font,
                        size: style.size,
                        color: style.color
                    )
                )
            }
        }
        composition.glyphs = next
    }

    // MARK: Style — v1 writes the same value to every glyph

    func mutateAllGlyphs(_ body: (inout Glyph) -> Void) {
        for index in composition.glyphs.indices {
            body(&composition.glyphs[index])
        }
    }

    func setFont(_ font: GlyphFont) {
        style.font = font
        mutateAllGlyphs { $0.font = font }
    }

    func setSize(_ size: CGFloat) {
        style.size = size
        mutateAllGlyphs { $0.size = size }
    }

    func setColor(_ color: RGBAColor) {
        style.color = color
        mutateAllGlyphs { $0.color = color }
    }

    /// Reopens a saved composition for further editing. Derives the v1/v2 single
    /// style from the first glyph so the style panel reflects what is on screen.
    func load(_ composition: Composition) {
        self.composition = composition
        if let first = composition.glyphs.first {
            style = GlyphStyle(font: first.font, size: first.size, color: first.color)
        }
    }

    /// Starts a fresh composition, keeping the current style as the starting point.
    func newComposition() {
        composition = Composition(
            aspectRatio: composition.aspectRatio,
            background: composition.background
        )
    }

    // MARK: Composition-level

    func setAspectRatio(_ ratio: AspectRatio) {
        composition.aspectRatio = ratio
    }

    func setEffectKind(_ kind: ShaderEffect.Kind) {
        composition.globalShader.kind = kind
        if kind != .none, composition.globalShader.intensity == 0 {
            composition.globalShader.intensity = 0.5
        }
    }

    func setEffectIntensity(_ intensity: Double) {
        composition.globalShader.intensity = intensity
    }

    func setBackground(_ background: Background) {
        composition.background = background
    }

    // MARK: Bindings for SwiftUI controls

    var colorBinding: Binding<Color> {
        Binding(
            get: { self.style.color.color },
            set: { self.setColor(RGBAColor($0)) }
        )
    }

    var backgroundColorBinding: Binding<Color> {
        Binding(
            get: {
                if case let .solid(rgba) = self.composition.background { rgba.color }
                else { Color.black }
            },
            set: { self.setBackground(.solid(RGBAColor($0))) }
        )
    }

    var sizeBinding: Binding<Double> {
        Binding(
            get: { Double(self.style.size) },
            set: { self.setSize(CGFloat($0)) }
        )
    }

    var intensityBinding: Binding<Double> {
        Binding(
            get: { self.composition.globalShader.intensity },
            set: { self.setEffectIntensity($0) }
        )
    }
}
