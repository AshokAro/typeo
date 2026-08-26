//
//  EditorView.swift
//  Typeo
//
//  Chrome lives here. Liquid Glass is used ONLY on these controls — never on the
//  canvas, which is content and gets exported. See CLAUDE.md conventions.
//

import SwiftUI
import SpriteKit

struct EditorView: View {
    let store: CompositionStore
    let library: CompositionLibrary

    @State private var showFontPicker = false
    @State private var showStylePanel = false
    @State private var exportImage: UIImage?
    @State private var isExporting = false
    @State private var didSave = false
    @State private var interaction: GlyphInteraction = .none
    @State private var isRecordingSheetUp = false
    @State private var activeFill: FillTarget?
    @State private var caretIndex: Int?
    @State private var isEditing = false
    @State private var expandedSlider: SliderTarget?
    @State private var amounts: [GlyphInteraction: Double] = Dictionary(
        uniqueKeysWithValues: GlyphInteraction.allCases.map { ($0, $0.defaultAmount) }
    )
    @State private var jumbleAmount: Double = 1

    enum SliderTarget: Hashable {
        case interaction(GlyphInteraction)
        case jumble
    }

    private var currentAmount: Double { amounts[interaction] ?? interaction.defaultAmount }
    @State private var scene = GlyphScene(
        composition: Composition(),
        size: AspectRatio.square.referenceSize
    )

    private var textBinding: Binding<String> {
        Binding(get: { store.text }, set: { store.text = $0 })
    }

    var body: some View {
        VStack(spacing: 12) {
            topBar

            GeometryReader { proxy in
                ZStack {
                    CanvasStage(
                        scene: scene,
                        composition: store.composition,
                        interaction: interaction,
                        interactionAmount: currentAmount,
                        availableSize: proxy.size
                    )
                    if store.composition.isEmpty {
                        emptyHint
                    }

                    HStack(alignment: .top, spacing: 8) {
                        Spacer(minLength: 0)
                        if let activeFill {
                            FillEditor(store: store, target: activeFill)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                        FillRail(store: store, active: $activeFill)
                    }
                    .padding(.trailing, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let expandedSlider {
                sliderRow(for: expandedSlider)
            }
            perLetterBar
            bottomBar
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .background(Color.black)
        .background(
            KeyInputBridge(
                isEditing: $isEditing,
                onInsert: { text in
                    let at = caretIndex ?? store.composition.glyphs.count
                    caretIndex = store.insertText(text, at: at)
                    scene.setCaret(index: caretIndex)
                },
                onDelete: {
                    let at = caretIndex ?? store.composition.glyphs.count
                    caretIndex = store.deleteBackward(at: at)
                    scene.setCaret(index: caretIndex)
                }
            )
            .frame(width: 0, height: 0)
        )
        .onAppear {
            scene.onCaretTap = { index in
                withAnimation(.snappy(duration: 0.2)) { activeFill = nil }
                caretIndex = index
                isEditing = true
                scene.setCaret(index: index)
            }
        }
        .onChange(of: isEditing) { _, editing in
            if !editing { scene.setCaret(index: nil); caretIndex = nil }
        }
        .onChange(of: interaction) { _, mode in
            // Interaction modes take over touches, so editing has to stop.
            if mode != .none { isEditing = false }
        }
        .sheet(isPresented: $showFontPicker) {
            FontPickerSheet(store: store).presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showStylePanel) {
            StylePanel(store: store).presentationDetents([.height(420), .large])
        }
        .sheet(isPresented: $isExporting) {
            if let exportImage { ExportSheet(image: exportImage) }
        }
        .sheet(isPresented: $isRecordingSheetUp) {
            RecordSheet(composition: store.composition, interaction: interaction)
        }
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack(spacing: 8) {
            // Scrolls, so adding modes later never squeezes the labels again.
            ScrollView(.horizontal, showsIndicators: false) {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(AspectRatio.allCases) { ratio in
                            AspectButton(ratio: ratio, isSelected: store.composition.aspectRatio == ratio) {
                                store.setAspectRatio(ratio)
                            }
                        }

                        Button { store.undo() } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 30, height: 26)
                        }
                        .buttonStyle(.glass)
                        .disabled(!store.canUndo)
                        .accessibilityLabel("Undo")

                        Button { store.redo() } label: {
                            Image(systemName: "arrow.uturn.forward")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 30, height: 26)
                        }
                        .buttonStyle(.glass)
                        .disabled(!store.canRedo)
                        .accessibilityLabel("Redo")
                    }
                    .padding(.trailing, 8)
                }
            }
            .scrollClipDisabled(false)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.92),
                        .init(color: .black.opacity(0), location: 1),
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
            )

            // Pinned: must never scroll out of reach.
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button { store.newComposition() } label: {
                        Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("New composition")

                    Button { saveToLibrary() } label: {
                        Image(systemName: didSave ? "checkmark" : "square.and.arrow.down")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.glass)
                    .disabled(store.composition.isEmpty)
                    .accessibilityLabel("Save to gallery")

                    Button { prepareExport() } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(store.composition.isEmpty)
                    .accessibilityLabel("Export")
                }
            }
        }
    }

    /// v3/v6. Everything on this row writes DIFFERENT values to individual glyphs.
    /// Long-press a mode or the shuffle button to reveal its slider.
    private var perLetterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(GlyphInteraction.allCases) { mode in
                        InteractionButton(mode: mode, isSelected: interaction == mode) {
                            interaction = mode
                            if mode == .none {
                                scene.reset()
                                expandedSlider = nil
                            } else {
                                withAnimation(.snappy(duration: 0.2)) {
                                    expandedSlider = .interaction(mode)
                                }
                            }
                        } onLongPress: {
                            guard mode != .none else { return }
                            interaction = mode
                            withAnimation(.snappy(duration: 0.2)) {
                                expandedSlider = .interaction(mode)
                            }
                        }
                    }

                    Divider().frame(height: 20).overlay(Color.white.opacity(0.2))

                    Button {
                        captureSceneTransforms()
                        isRecordingSheetUp = true
                    } label: {
                        Image(systemName: "video").font(.system(size: 14, weight: .semibold))
                            .frame(width: 30, height: 24)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Record video")

                    Button {
                        store.jumble(.init(amount: jumbleAmount))
                    } label: {
                        Image(systemName: "shuffle").font(.system(size: 14, weight: .semibold))
                            .frame(width: 30, height: 24)
                    }
                    .buttonStyle(.glass)
                    .disabled(store.composition.isEmpty)
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                            withAnimation(.snappy(duration: 0.2)) { expandedSlider = .jumble }
                        }
                    )
                    .accessibilityLabel("Shuffle letters. Long press for amount.")

                    Button {
                        store.unjumble()
                        scene.reset()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 30, height: 24)
                    }
                    .buttonStyle(.glass)
                    .disabled(!store.isJumbled)
                    .accessibilityLabel("Reset letters")
                }
                .padding(.trailing, 8)
            }
        }
    }

    // Not @ViewBuilder: it computes bindings first and returns a single view.
    private func sliderRow(for target: SliderTarget) -> some View {
        let title: String
        let value: Binding<Double>
        let detail: String

        switch target {
        case let .interaction(mode):
            title = mode.amountLabel
            value = Binding(
                get: { amounts[mode] ?? mode.defaultAmount },
                set: { amounts[mode] = $0 }
            )
            detail = mode == .attract && (amounts[mode] ?? 1) < 0.04 ? "zero gravity" : ""
        case .jumble:
            title = "Shuffle"
            value = $jumbleAmount
            detail = "\(letterCount(for: jumbleAmount))/\(glyphCount) letters"
        }

        return HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 58, alignment: .leading)

            Slider(value: value, in: 0...1)

            Text(detail.isEmpty ? "\(Int(value.wrappedValue * 100))%" : detail)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: 74, alignment: .trailing)

            Button {
                withAnimation(.snappy(duration: 0.2)) { expandedSlider = nil }
            } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var glyphCount: Int {
        store.composition.glyphs.filter { $0.role == .glyph }.count
    }

    private func letterCount(for amount: Double) -> Int {
        guard glyphCount > 0, amount > 0 else { return 0 }
        return max(1, Int((Double(glyphCount) * amount).rounded()))
    }

    private var bottomBar: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                Button { showFontPicker = true } label: {
                    Label(currentFontName, systemImage: "textformat")
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                }
                .buttonStyle(.glass)

                Button { showStylePanel = true } label: {
                    Label("Style", systemImage: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                }
                .buttonStyle(.glass)

                if isEditing {
                    Button { isEditing = false } label: {
                        Text("Done")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.glassProminent)
                }
            }
        }
    }

    private var emptyHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "character.cursor.ibeam").font(.system(size: 26, weight: .light))
            Text("Tap the canvas to type").font(.system(size: 15, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.35))
        .allowsHitTesting(false)
    }

    private var currentFontName: String {
        store.isJumbled ? "Mixed" : (FontCatalog.option(matching: store.style.font)?.displayName ?? "Font")
    }

    // MARK: Actions

    /// Node positions live in the scene while you play with them. Both saving and
    /// exporting pull them back onto the model first, so what you see is what is stored.
    private func captureSceneTransforms() {
        store.applyTransforms(scene.glyphTransforms())
    }

    private func saveToLibrary() {
        captureSceneTransforms()
        guard library.save(store.composition) else { return }
        withAnimation(.snappy) { didSave = true }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(.snappy) { didSave = false }
        }
    }

    private func prepareExport() {
        isEditing = false
        captureSceneTransforms()
        guard let image = CompositionRenderer.render(store.composition, time: 0, scale: 2) else { return }
        exportImage = image
        isExporting = true
    }
}

private struct AspectButton: View {
    let ratio: AspectRatio
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        if isSelected { button.buttonStyle(.glassProminent) }
        else { button.buttonStyle(.glass) }
    }

    private var button: some View {
        // Icon-only: the three shapes are self-describing, and the top bar has to fit
        // six controls. The ratio is still announced to VoiceOver.
        Button(action: action) {
            Image(systemName: ratio.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 30, height: 26)
        }
        .accessibilityLabel("Aspect ratio \(ratio.label)")
    }
}

private struct InteractionButton: View {
    let mode: GlyphInteraction
    let isSelected: Bool
    let action: () -> Void
    var onLongPress: () -> Void = {}

    var body: some View {
        Group {
            if isSelected { button.buttonStyle(.glassProminent) }
            else { button.buttonStyle(.glass) }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.35).onEnded { _ in onLongPress() }
        )
    }

    private var button: some View {
        Button(action: action) {
            Label(mode.label, systemImage: mode.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .labelStyle(.iconOnly)
                .frame(width: 30, height: 24)
        }
        .accessibilityLabel(mode.label)
    }
}
