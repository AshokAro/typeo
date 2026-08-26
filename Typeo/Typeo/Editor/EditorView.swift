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

    @FocusState private var isTyping: Bool
    @State private var showFontPicker = false
    @State private var showStylePanel = false
    @State private var exportImage: UIImage?
    @State private var isExporting = false
    @State private var didSave = false
    @State private var interaction: GlyphInteraction = .none
    @State private var isRecordingSheetUp = false
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
                        availableSize: proxy.size
                    )
                    if store.composition.isEmpty {
                        emptyHint
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.rect)
                .onTapGesture { if store.composition.isEmpty { isTyping = true } }
            }

            if !store.composition.isEmpty {
                perLetterBar
            }
            bottomBar
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .background(Color.black)
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
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(AspectRatio.allCases) { ratio in
                    AspectButton(ratio: ratio, isSelected: store.composition.aspectRatio == ratio) {
                        store.setAspectRatio(ratio)
                    }
                }

                Spacer(minLength: 6)

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

    /// v3. Everything on this row writes DIFFERENT values to individual glyphs.
    private var perLetterBar: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(GlyphInteraction.allCases) { mode in
                    InteractionButton(mode: mode, isSelected: interaction == mode) {
                        interaction = mode
                        if mode == .none { scene.reset() }
                    }
                }

                Spacer(minLength: 4)

                Button {
                    captureSceneTransforms()
                    isRecordingSheetUp = true
                } label: {
                    Image(systemName: "video").font(.system(size: 14, weight: .semibold))
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Record video")

                Button { store.jumble() } label: {
                    Image(systemName: "shuffle").font(.system(size: 14, weight: .semibold))
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Jumble letters")

                Button {
                    store.unjumble()
                    scene.reset()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(.glass)
                .disabled(!store.isJumbled)
                .accessibilityLabel("Reset letters")
            }
        }
    }

    private var bottomBar: some View {
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 10) {
                TextField("Tap to type", text: textBinding, axis: .vertical)
                    .focused($isTyping)
                    .font(.system(size: 17, weight: .medium))
                    .lineLimit(1...3)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .glassEffect(.regular, in: .rect(cornerRadius: 18))

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
                        Label("Style", systemImage: "paintpalette")
                            .font(.system(size: 14, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.glass)

                    if isTyping {
                        Button { isTyping = false } label: {
                            Text("Done")
                                .font(.system(size: 14, weight: .semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                        }
                        .buttonStyle(.glassProminent)
                    }
                }
            }
        }
    }

    private var emptyHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "character.cursor.ibeam").font(.system(size: 26, weight: .light))
            Text("Tap to type").font(.system(size: 15, weight: .medium))
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
        isTyping = false
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

    var body: some View {
        if isSelected { button.buttonStyle(.glassProminent) }
        else { button.buttonStyle(.glass) }
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
