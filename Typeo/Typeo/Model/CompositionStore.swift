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

    // MARK: Undo / redo
    //
    // Snapshots whole Compositions. The model is a value type and small, so this is
    // simpler and far less bug-prone than recording inverse operations.

    private var undoStack: [Composition] = []
    private var redoStack: [Composition] = []
    private var lastCheckpoint: (kind: String, at: Date)?
    private let undoLimit = 60

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Records a restore point. Repeated checkpoints of the same `kind` inside
    /// `coalesceFor` collapse into one, so typing does not fill the stack per keystroke.
    func checkpoint(_ kind: String, coalesceFor window: TimeInterval = 0) {
        if window > 0,
           let last = lastCheckpoint,
           last.kind == kind,
           Date().timeIntervalSince(last.at) < window {
            lastCheckpoint = (kind, Date())
            return
        }
        undoStack.append(composition)
        if undoStack.count > undoLimit { undoStack.removeFirst() }
        redoStack.removeAll()
        lastCheckpoint = (kind, Date())
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(composition)
        composition = previous
        syncStyleFromComposition()
        lastCheckpoint = nil
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(composition)
        composition = next
        syncStyleFromComposition()
        lastCheckpoint = nil
    }

    private func syncStyleFromComposition() {
        if let first = composition.glyphs.first {
            style = GlyphStyle(font: first.font, size: first.size, color: first.color)
        }
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
        checkpoint("text", coalesceFor: 1.2)
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

    // MARK: In-canvas editing (v6)
    //
    // Text is edited on the canvas now, so edits are insert/delete at a caret index
    // rather than a whole-string replacement. Glyphs either side of the caret keep
    // their identity and per-letter styling, which setText's positional reconcile
    // could not guarantee.

    /// Inserts at `index` and returns the caret position after the insertion.
    @discardableResult
    func insertText(_ text: String, at index: Int) -> Int {
        guard !text.isEmpty else { return index }
        checkpoint("text", coalesceFor: 1.2)
        let clamped = min(max(0, index), composition.glyphs.count)
        let inserted = text.map { character in
            Glyph(
                character: String(character),
                font: style.font,
                size: style.size,
                color: style.color
            )
        }
        composition.glyphs.insert(contentsOf: inserted, at: clamped)
        return clamped + inserted.count
    }

    /// Deletes the glyph before `index` and returns the new caret position.
    @discardableResult
    func deleteBackward(at index: Int) -> Int {
        guard index > 0, index <= composition.glyphs.count else { return index }
        checkpoint("text", coalesceFor: 1.2)
        composition.glyphs.remove(at: index - 1)
        return index - 1
    }

    // MARK: Layout (v6)

    func setAlignment(_ alignment: TextBlockAlignment) {
        checkpoint("alignment")
        composition.alignment = alignment
    }

    func setLetterSpacing(_ value: Double) {
        checkpoint("spacing", coalesceFor: 0.8)
        composition.letterSpacing = value
    }

    func setLineHeight(_ value: Double) {
        checkpoint("lineHeight", coalesceFor: 0.8)
        composition.lineHeightMultiple = value
    }

    var letterSpacingBinding: Binding<Double> {
        Binding(get: { self.composition.letterSpacing ?? 0 }, set: { self.setLetterSpacing($0) })
    }

    var lineHeightBinding: Binding<Double> {
        Binding(get: { self.composition.lineHeightMultiple ?? 1 }, set: { self.setLineHeight($0) })
    }

    // MARK: Style — v1 writes the same value to every glyph

    func mutateAllGlyphs(_ body: (inout Glyph) -> Void) {
        for index in composition.glyphs.indices {
            body(&composition.glyphs[index])
        }
    }

    func setFont(_ font: GlyphFont) {
        checkpoint("font")
        style.font = font
        mutateAllGlyphs { $0.font = font }
    }

    func setSize(_ size: CGFloat) {
        checkpoint("size", coalesceFor: 0.8)
        style.size = size
        mutateAllGlyphs { $0.size = size }
    }

    func setColor(_ color: RGBAColor) {
        checkpoint("colour", coalesceFor: 0.8)
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

    // MARK: v3 — per-glyph divergence
    //
    // Everything above writes the SAME value to every glyph. Everything below writes
    // DIFFERENT values to individual glyphs. The model did not change to allow this;
    // positionOffset, rotation and per-glyph font/size/colour have existed since v1.

    /// Stores the live scene's node transforms back onto the glyphs, so an export or a
    /// save captures where the letters actually are.
    func applyTransforms(_ transforms: [UUID: (offset: CGPoint, rotation: Double)]) {
        for index in composition.glyphs.indices {
            guard let transform = transforms[composition.glyphs[index].id] else { continue }
            composition.glyphs[index].positionOffset = transform.offset
            composition.glyphs[index].rotation = transform.rotation
        }
    }

    struct JumbleOptions {
        var fonts = true
        var sizes = true
        var colors = false
        var rotation = true
        /// Fraction of letters that change, 0...1. Low values touch one or two letters;
        /// 1 randomises everything, which is what v3 always did.
        var amount: Double = 1
    }

    func jumble(_ options: JumbleOptions = JumbleOptions()) {
        checkpoint("jumble")

        let eligible = composition.glyphs.indices.filter { composition.glyphs[$0].role == .glyph }
        guard !eligible.isEmpty else { return }

        let fraction = min(max(options.amount, 0), 1)
        let count = fraction <= 0 ? 0 : max(1, Int((Double(eligible.count) * fraction).rounded()))
        let chosen = Set(eligible.shuffled().prefix(count))

        for index in eligible where chosen.contains(index) {
            if options.fonts, let option = FontCatalog.all.randomElement() {
                composition.glyphs[index].font = option.glyphFont
            }
            if options.sizes {
                composition.glyphs[index].size = (style.size * CGFloat.random(in: 0.6...1.5))
                    .rounded()
            }
            if options.colors {
                composition.glyphs[index].color = RGBAColor(
                    Color(hue: Double.random(in: 0...1), saturation: 0.75, brightness: 1)
                )
            }
            if options.rotation {
                composition.glyphs[index].rotation = Double.random(in: -20...20)
            }
        }
    }

    /// Puts every glyph back on the single shared style and clears any displacement.
    func unjumble() {
        checkpoint("unjumble")
        mutateAllGlyphs { glyph in
            glyph.font = style.font
            glyph.size = style.size
            glyph.color = style.color
            glyph.positionOffset = .zero
            glyph.rotation = 0
        }
    }

    var isJumbled: Bool {
        let glyphs = composition.glyphs.filter { $0.role == .glyph }
        guard !glyphs.isEmpty else { return false }
        return Set(glyphs.map(\.font)).count > 1
            || Set(glyphs.map(\.size)).count > 1
            || glyphs.contains { $0.rotation != 0 || $0.positionOffset != .zero }
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

    func setEffectSecondary(_ value: Double) {
        checkpoint("effect", coalesceFor: 0.8)
        composition.globalShader.secondary = value
    }

    func setEffectIntensity(_ intensity: Double) {
        composition.globalShader.intensity = intensity
    }

    func setBackground(_ background: Background) {
        checkpoint("background", coalesceFor: 0.8)
        composition.background = background
    }

    func apply(_ preset: StylePreset) {
        checkpoint("preset")
        style.font = preset.font
        style.color = preset.color
        mutateAllGlyphs { glyph in
            glyph.font = preset.font
            glyph.color = preset.color
        }
        composition.textGradient = preset.textGradient
        composition.background = preset.background
        composition.globalShader = preset.shader
    }

    // MARK: Fills

    func setTextGradient(_ gradient: GradientPaint?) {
        checkpoint("textFill", coalesceFor: 0.8)
        composition.textGradient = gradient
    }

    var textGradient: GradientPaint? { composition.textGradient }

    var backgroundGradient: GradientPaint? {
        if case let .linearGradient(colors, angle) = composition.background {
            return GradientPaint(colors: colors, angleDegrees: angle)
        }
        return nil
    }

    func setBackgroundGradient(_ gradient: GradientPaint?) {
        if let gradient {
            setBackground(.linearGradient(colors: gradient.colors, angleDegrees: gradient.angleDegrees))
        } else {
            setBackground(.solid(RGBAColor(backgroundColorBinding.wrappedValue)))
        }
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
