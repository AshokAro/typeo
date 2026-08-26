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
    @State private var isLocked = false
    @State private var collisionsOn = false
    /// Which detent the open sheet is sitting at, so the canvas knows how much room
    /// it actually has above it.
    @State private var sheetDetent: PresentationDetent = Self.shortSheet
    @State private var recordedVideo: URL?
    @State private var recordingRemaining: Int?
    @State private var recordingTask: Task<Void, Never>?
    @State private var caretIndex: Int?
    @State private var isEditing = false
    @State private var expandedSlider: SliderTarget?
    @State private var amounts: [GlyphInteraction: Double] = Dictionary(
        uniqueKeysWithValues: GlyphInteraction.allCases.map { ($0, $0.defaultAmount) }
    )
    @State private var jumbleAmount: Double = 0
    /// Set as soon as a mode moves letters, so Reset is enabled for scene-only state.
    @State private var didInteract = false

    enum SliderTarget: Hashable {
        case interaction(GlyphInteraction)
        case jumble
    }

    private var currentAmount: Double { amounts[interaction] ?? interaction.defaultAmount }
    private var isSheetOpen: Bool { showStylePanel || showFontPicker }

    /// The style and type sheets stop at 70% of the screen so the canvas is never
    /// hidden behind what is being changed.
    static let shortSheet = PresentationDetent.fraction(0.45)
    static let tallSheet = PresentationDetent.fraction(0.7)

    /// How much of the canvas area is still visible above the open sheet. Measured
    /// against the chrome rather than derived: the canvas area already excludes the
    /// top bar, so the fractions are not simply 1 minus the detent.
    private var canvasHeightFactor: CGFloat {
        guard isSheetOpen else { return 1 }
        return sheetDetent == Self.tallSheet ? 0.32 : 0.66
    }
    @State private var scene = GlyphScene(
        composition: Composition(),
        size: AspectRatio.square.referenceSize
    )

    private var textBinding: Binding<String> {
        Binding(get: { store.text }, set: { store.text = $0 })
    }

    var body: some View {
        VStack(spacing: 10) {
            topBar
                .padding(.horizontal, 16)

            GeometryReader { proxy in
                ZStack {
                    CanvasStage(
                        scene: scene,
                        composition: store.composition,
                        interaction: interaction,
                        interactionAmount: currentAmount,
                        collisions: collisionsOn,
                        availableSize: CGSize(
                            width: proxy.size.width,
                            height: proxy.size.height * canvasHeightFactor
                        )
                    )
                    .frame(maxHeight: .infinity, alignment: isSheetOpen ? .top : .center)
                    .animation(.snappy(duration: 0.25), value: canvasHeightFactor)
                    if store.composition.isEmpty {
                        emptyHint
                    }
                    if let countdown = recordingRemaining {
                        recordingOverlay(countdown)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 16)

            if let expandedSlider {
                sliderRow(for: expandedSlider)
                    .padding(.horizontal, 16)
            }

            modeBar

            bottomBar
                .padding(.horizontal, 16)
        }
        .padding(.bottom, 6)
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
            scene.onInteractionBegan = { didInteract = true }
            scene.onCaretTap = { index in
                caretIndex = index
                isEditing = true
                scene.setCaret(index: index)
            }
        }
        .onChange(of: isEditing) { _, editing in
            if !editing { scene.setCaret(index: nil); caretIndex = nil }
        }
        .onChange(of: interaction) { _, mode in
            if mode != .none { isEditing = false }
        }
        .onChange(of: isLocked) { _, locked in
            scene.isLocked = locked
        }
        // Half height, scrolling inside, and the canvas behind stays interactive so
        // effects can be tried without dismissing the sheet.
        .sheet(isPresented: $showFontPicker, onDismiss: { sheetDetent = Self.shortSheet }) {
            FontPickerSheet(store: store).modifier(EditorSheetLayout(detent: $sheetDetent))
        }
        .sheet(isPresented: $showStylePanel, onDismiss: { sheetDetent = Self.shortSheet }) {
            StylePanel(store: store).modifier(EditorSheetLayout(detent: $sheetDetent))
        }
        .sheet(isPresented: $isExporting) {
            if let exportImage { ExportSheet(image: exportImage) }
        }
        .sheet(isPresented: $isRecordingSheetUp) {
            if let recordedVideo {
                RecordedVideoSheet(url: recordedVideo, aspectRatio: store.composition.aspectRatio)
            }
        }
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack(spacing: 8) {
            // Three pills collapsed into one menu, which is what freed room for
            // undo/redo without scrolling.
            Menu {
                Picker("Aspect ratio", selection: Binding(
                    get: { store.composition.aspectRatio },
                    set: { store.setAspectRatio($0) }
                )) {
                    ForEach(AspectRatio.allCases) { ratio in
                        Label(ratio.label, systemImage: ratio.systemImage).tag(ratio)
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: store.composition.aspectRatio.systemImage)
                        .font(.system(size: 13, weight: .semibold))
                    Text(store.composition.aspectRatio.label)
                        .font(.system(size: 13, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .frame(height: 26)
                .padding(.horizontal, 10)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Aspect ratio \(store.composition.aspectRatio.label)")

            Button { store.undo() } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 28, height: 26)
            }
            .buttonStyle(.glass)
            .disabled(!store.canUndo)
            .accessibilityLabel("Undo")

            Button { store.redo() } label: {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 28, height: 26)
            }
            .buttonStyle(.glass)
            .disabled(!store.canRedo)
            .accessibilityLabel("Redo")

            Spacer(minLength: 4)

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

            // Share is secondary now, and carries the photo/video choice.
            Menu {
                Button {
                    prepareExport()
                } label: {
                    Label("Save as Photo", systemImage: "photo")
                }
                Button {
                    beginVideoRecording()
                } label: {
                    Label("Record Video", systemImage: "video")
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.glass)
            .disabled(store.composition.isEmpty)
            .accessibilityLabel("Share")
        }
    }

    /// v3/v6. Everything on this row writes DIFFERENT values to individual glyphs.
    /// Long-press a mode to reveal its slider.
    /// v3/v6. Everything on this row writes DIFFERENT values to individual glyphs.
    /// One tap selects a mode AND opens its slider — there is nothing behind a long
    /// press any more.
    private var modeBar: some View {
        // One row, one scroll view. Splitting the fixed controls out into a sibling
        // HStack squeezed the modes into a narrower scroll view than their own
        // content, and the shuffle pill was clipped away entirely.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(GlyphInteraction.allCases) { mode in
                    InteractionButton(mode: mode, isSelected: isSelected(mode)) {
                        select(mode)
                    }
                }

                // Shuffle is a mode like the rest now: it just mutates the model
                // instead of responding to a touch.
                ShuffleButton(isSelected: expandedSlider == .jumble) {
                    selectShuffle()
                }
                .disabled(store.composition.isEmpty)

                Divider().frame(height: 20).overlay(Color.white.opacity(0.2))

                // Was on the floating rail. A toggle belongs with the modes it holds
                // in place, and the rail was covering the canvas to say so.
                ToggleButton(
                    systemImage: isLocked ? "lock.fill" : "lock.open",
                    isOn: isLocked,
                    label: isLocked ? "Unlock effect" : "Lock effect in place"
                ) {
                    isLocked.toggle()
                }

                ToggleButton(
                    systemImage: "circlebadge.2.fill",
                    isOn: collisionsOn,
                    label: collisionsOn ? "Turn off letter collision" : "Letters collide"
                ) {
                    collisionsOn.toggle()
                    didInteract = true
                }

                Button { resetLetters() } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 20, height: 24)
                }
                .buttonStyle(.glass)
                .disabled(!canReset)
                .accessibilityLabel("Reset letters")
            }
            // Small control size: eight pills at the default size ran a long way past
            // the screen, and Reset was the one pushed off.
            .controlSize(.small)
            // Vertical room so a pressed pill's glass is not sliced off, and the row
            // runs edge to edge instead of stopping at the page margin.
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
        }
        .scrollClipDisabled()
    }

    private func isSelected(_ mode: GlyphInteraction) -> Bool {
        guard expandedSlider != .jumble else { return false }
        return interaction == mode
    }

    private func select(_ mode: GlyphInteraction) {
        store.endLiveJumble()
        interaction = mode
        withAnimation(.snappy(duration: 0.2)) {
            expandedSlider = mode == .none ? nil : .interaction(mode)
        }
    }

    /// Tapping shuffle rolls a fresh scatter. Tapping it again re-rolls, which is why
    /// it both selects the pill and does the work.
    private func selectShuffle() {
        interaction = .none
        isEditing = false
        store.beginLiveJumble()
        store.updateLiveJumble(amount: jumbleAmount)
        withAnimation(.snappy(duration: 0.2)) { expandedSlider = .jumble }
    }

    /// Reset lights up the moment anything has actually been applied to the letters —
    /// including a held drop, which never reaches the model and so cannot be seen by
    /// asking the composition.
    private var canReset: Bool {
        store.isJumbled || didInteract || currentAmount != 0
    }

    private func resetLetters() {
        store.endLiveJumble()
        store.unjumble()
        scene.reset()
        jumbleAmount = 0
        for mode in GlyphInteraction.allCases { amounts[mode] = mode.defaultAmount }
        didInteract = false
        withAnimation(.snappy(duration: 0.2)) { expandedSlider = nil }
        interaction = .none
    }

    // Not @ViewBuilder: it computes bindings first and returns a single view.
    private func sliderRow(for target: SliderTarget) -> some View {
        let title: String
        let value: Binding<Double>
        let detail: String
        let range: ClosedRange<Double>

        switch target {
        case let .interaction(mode):
            title = mode.amountLabel
            value = Binding(
                get: { amounts[mode] ?? mode.defaultAmount },
                set: { amounts[mode] = $0 }
            )
            // Use the mode's OWN range. Hardcoding 0...1 here is what made pucker and
            // float-up unreachable even though the model allowed them.
            range = mode.amountRange
            detail = mode.amountDetail(amounts[mode] ?? mode.defaultAmount)
        case .jumble:
            title = "Shuffle"
            value = Binding(
                get: { jumbleAmount },
                set: { newValue in
                    jumbleAmount = newValue
                    store.updateLiveJumble(amount: newValue)   // live, every tick
                }
            )
            range = 0...1
            // The slider only governs how many letters get a NEW TYPEFACE. Every letter
            // is scattered regardless, so naming them "letters" read as a lie at zero.
            detail = "\(letterCount(for: jumbleAmount))/\(glyphCount) restyled"
        }

        let isBipolar = range.lowerBound < 0

        return HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 54, alignment: .leading)

            SnappingSlider(value: value, range: range)

            Button {
                value.wrappedValue = isBipolar ? 0 : value.wrappedValue
            } label: {
                Text(detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(minWidth: 78, alignment: .trailing)
            }
            .buttonStyle(.plain)
            .disabled(!isBipolar)
            .accessibilityLabel(isBipolar ? "Reset \(title) to zero" : detail)

            Button {
                if case .jumble = target { store.endLiveJumble() }
                withAnimation(.snappy(duration: 0.2)) { expandedSlider = nil }
                if case .jumble = target {} else { interaction = .none }
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

    // MARK: Video

    private static let recordingSeconds = 4

    /// Records what you do on the canvas for a few seconds, then replays those touches
    /// offscreen at full resolution. Capturing the live view instead would be pinned to
    /// the screen's scale and would drop frames under load.
    private func beginVideoRecording() {
        guard !store.composition.isEmpty, recordingRemaining == nil else { return }
        isEditing = false
        recordedVideo = nil

        scene.beginTouchRecording()
        let seconds = Self.recordingSeconds
        recordingRemaining = seconds

        recordingTask = Task {
            for remaining in stride(from: seconds, through: 1, by: -1) {
                recordingRemaining = remaining
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { recordingRemaining = nil; return }
            }
            recordingRemaining = nil

            let track = scene.endTouchRecording()
            do {
                let url = try await VideoExporter.export(
                    composition: store.composition,
                    interaction: interaction,
                    interactionAmount: currentAmount,
                    collisions: collisionsOn,
                    touchTrack: track,
                    settings: VideoExportSettings(
                        duration: Double(seconds),
                        framesPerSecond: 30,
                        scale: 1
                    )
                )
                recordedVideo = url
                isRecordingSheetUp = true
            } catch {
                recordedVideo = nil
            }
        }
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

    private func recordingOverlay(_ remaining: Int) -> some View {
        VStack {
            HStack(spacing: 7) {
                Circle().fill(.red).frame(width: 9, height: 9)
                Text("Recording · \(remaining)s")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassEffect(.regular, in: .capsule)
            .padding(.top, 12)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
        .accessibilityLabel("Recording, \(remaining) seconds left")
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

/// Both editor sheets share one presentation: two detents, the taller capped at 70%,
/// with the canvas behind still interactive so an effect can be tried without
/// dismissing the panel.
private struct EditorSheetLayout: ViewModifier {
    @Binding var detent: PresentationDetent

    func body(content: Content) -> some View {
        content
            .presentationDetents([EditorView.shortSheet, EditorView.tallSheet], selection: $detent)
            // Opaque, not a material: the lit mode pills behind the sheet smeared
            // through the blur and read as a stain across the panel.
            .presentationBackground(Color(uiColor: .systemGroupedBackground))
            .presentationBackgroundInteraction(.enabled(upThrough: EditorView.tallSheet))
            .presentationDragIndicator(.visible)
    }
}

/// A pill that stays lit while it is on — lock, and in Stage 3 collision.
struct ToggleButton: View {
    let systemImage: String
    let isOn: Bool
    let label: String
    let action: () -> Void

    var body: some View {
        Group {
            if isOn { button.buttonStyle(.glassProminent) }
            else { button.buttonStyle(.glass) }
        }
    }

    private var button: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 20, height: 24)
        }
        .accessibilityLabel(label)
    }
}

private struct InteractionButton: View {
    let mode: GlyphInteraction
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Group {
            if isSelected { button.buttonStyle(.glassProminent) }
            else { button.buttonStyle(.glass) }
        }
    }

    private var button: some View {
        Button(action: action) {
            Label(mode.label, systemImage: mode.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .labelStyle(.iconOnly)
                .frame(width: 20, height: 24)
        }
        .accessibilityLabel(mode.label)
    }
}

private struct ShuffleButton: View {
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        if isSelected { button.buttonStyle(.glassProminent) }
        else { button.buttonStyle(.glass) }
    }

    private var button: some View {
        Button(action: action) {
            Image(systemName: "shuffle")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 20, height: 24)
        }
        .accessibilityLabel("Shuffle letters")
    }
}
