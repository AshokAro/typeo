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

    @FocusState private var isTyping: Bool
    @State private var showFontPicker = false
    @State private var showStylePanel = false
    @State private var exportImage: UIImage?
    @State private var isExporting = false

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
                        availableSize: proxy.size
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

    private func prepareExport() {
        isTyping = false
        guard let image = CompositionRenderer.render(store.composition, scale: 2) else { return }
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
