//
//  EditorView.swift
//  Typeo
//
//  Chrome lives here. Liquid Glass is used ONLY on these controls — never on the
//  canvas, which is content and gets exported. See CLAUDE.md conventions.
//

import SwiftUI

struct EditorView: View {
    let store: CompositionStore
    let library: CompositionLibrary

    @FocusState private var isTyping: Bool
    @State private var showFontPicker = false
    @State private var showStylePanel = false
    @State private var exportImage: UIImage?
    @State private var isExporting = false
    /// One clock shared by the live canvas and the exporter, so the exported frame
    /// is the frame that was on screen when Export was tapped.
    @State private var animationStart = Date()
    @State private var didSave = false

    private var textBinding: Binding<String> {
        Binding(get: { store.text }, set: { store.text = $0 })
    }

    var body: some View {
        VStack(spacing: 14) {
            topBar

            GeometryReader { proxy in
                ZStack {
                    CanvasStage(
                        composition: store.composition,
                        availableSize: proxy.size,
                        animationStart: animationStart
                    )
                    if store.composition.isEmpty {
                        emptyHint
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.rect)
                .onTapGesture { isTyping = true }
            }

            bottomBar
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .background(Color.black)
        .sheet(isPresented: $showFontPicker) {
            FontPickerSheet(store: store)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showStylePanel) {
            StylePanel(store: store)
                .presentationDetents([.height(420), .large])
        }
        .sheet(isPresented: $isExporting) {
            if let exportImage {
                ExportSheet(image: exportImage)
            }
        }
    }

    // MARK: Chrome

    private var topBar: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(AspectRatio.allCases) { ratio in
                    AspectButton(
                        ratio: ratio,
                        isSelected: store.composition.aspectRatio == ratio
                    ) {
                        store.setAspectRatio(ratio)
                    }
                }

                Spacer(minLength: 8)

                Button {
                    store.newComposition()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 28, height: 26)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("New composition")

                Button {
                    saveToLibrary()
                } label: {
                    Image(systemName: didSave ? "checkmark" : "square.and.arrow.down")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 28, height: 26)
                }
                .buttonStyle(.glass)
                .disabled(store.composition.isEmpty)
                .accessibilityLabel("Save to gallery")

                Button {
                    prepareExport()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 30, height: 26)
                }
                .buttonStyle(.glassProminent)
                .disabled(store.composition.isEmpty)
                .accessibilityLabel("Export")
            }
        }
    }

    private var bottomBar: some View {
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 10) {
                TextField("Tap to type", text: textBinding, axis: .vertical)
                    .focused($isTyping)
                    .font(.system(size: 17, weight: .medium))
                    .lineLimit(1...4)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.return)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .glassEffect(.regular, in: .rect(cornerRadius: 18))

                HStack(spacing: 8) {
                    Button {
                        showFontPicker = true
                    } label: {
                        Label(currentFontName, systemImage: "textformat")
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.glass)

                    Button {
                        showStylePanel = true
                    } label: {
                        Label("Style", systemImage: "paintpalette")
                            .font(.system(size: 14, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.glass)

                    if isTyping {
                        Button {
                            isTyping = false
                        } label: {
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
            Image(systemName: "character.cursor.ibeam")
                .font(.system(size: 26, weight: .light))
            Text("Tap to type")
                .font(.system(size: 15, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.35))
        .allowsHitTesting(false)
    }

    private var currentFontName: String {
        FontCatalog.option(matching: store.style.font)?.displayName ?? "Font"
    }

    private func saveToLibrary() {
        guard library.save(store.composition) else { return }
        withAnimation(.snappy) { didSave = true }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(.snappy) { didSave = false }
        }
    }

    private func prepareExport() {
        isTyping = false
        let time = Date().timeIntervalSince(animationStart)
        guard let image = CompositionRenderer.render(store.composition, time: time, scale: 2) else { return }
        exportImage = image
        isExporting = true
    }
}

private struct AspectButton: View {
    let ratio: AspectRatio
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        if isSelected {
            button.buttonStyle(.glassProminent)
        } else {
            button.buttonStyle(.glass)
        }
    }

    private var button: some View {
        Button(action: action) {
            Label(ratio.label, systemImage: ratio.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 4)
                .frame(height: 26)
        }
        .accessibilityLabel("Aspect ratio \(ratio.label)")
    }
}
