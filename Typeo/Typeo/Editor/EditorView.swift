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
    @State private var tiltSource = TiltSource()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Which detent the open sheet is sitting at, so the canvas knows how much room
    /// it actually has above it.
    @State private var sheetDetent: PresentationDetent = Self.shortSheet
    @State private var recordedVideo: URL?
    @State private var recording: RecordingPhase = .idle
    /// Export failures used to be swallowed: the sheet simply never appeared and the
    /// user was left guessing.
    @State private var exportError: String?
    @State private var recordingTask: Task<Void, Never>?

    /// Recording is a countdown, then an open-ended take the user ends themselves.
    /// A fixed length meant composing the whole performance before pressing the button.
    enum RecordingPhase: Equatable {
        case idle
        case countdown(Int)
        case running(TimeInterval)
        case rendering(Double)

        var isBusy: Bool { self != .idle }
    }
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
                        showsEmptyHint: store.composition.isEmpty,
                        onAccessibilityActivate: { beginEditing(at: store.composition.glyphs.count) },
                        availableSize: CGSize(
                            width: proxy.size.width,
                            height: proxy.size.height * canvasHeightFactor
                        )
                    )
                    .frame(maxHeight: .infinity, alignment: isSheetOpen ? .top : .center)
                    .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: canvasHeightFactor)
                    if recording.isBusy {
                        recordingOverlay
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
        // The editor chrome is a fixed grid of controls around the artwork. Text still
        // scales, but past this the bars would push the canvas off the screen; the
        // sheets, where the reading happens, are uncapped.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
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
            scene.onCaretTap = { index in beginEditing(at: index) }
        }
        .onChange(of: isEditing) { _, editing in
            if !editing { scene.setCaret(index: nil); caretIndex = nil }
        }
        .onChange(of: interaction) { _, mode in
            if mode != .none { isEditing = false }
            // The sensor runs ONLY while the mode is selected. Device motion at 60Hz
            // is not something to leave on in the background.
            if mode == .tilt {
                tiltSource.onUpdate = { [scene] vector in scene.tilt = vector }
                tiltSource.start()
            } else {
                tiltSource.stop()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, interaction == .tilt { tiltSource.start() }
            else { tiltSource.stop() }
        }
        .onDisappear { tiltSource.stop() }
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
        .alert("Export failed", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
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
            HStack(spacing: 3) {
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

                // A gap instead of a divider: the rule cost more width than the space
                // it was standing in.
                Spacer(minLength: 8)

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
                        .frame(width: 17, height: 30)
                }
                .buttonStyle(.glass)
                .disabled(!canReset)
                .accessibilityLabel("Reset letters")
            }
            // .glass carries a fixed ~23pt of padding per pill and ignores controlSize,
            // so the ICON frame is the only lever on how many fit. Nine is the limit at
            // 17pt; a tenth control has to go somewhere else.
            .controlSize(.small)
            // Vertical room so a pressed pill's glass is not sliced off, and the row
            // runs edge to edge instead of stopping at the page margin.
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
        }
        .scrollClipDisabled()
    }

    /// Chrome animation, honouring Reduce Motion in one place rather than at every
    /// call site.
    private var chromeAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.2)
    }

    /// Places the caret and raises the keyboard. Shared by a tap on the canvas and by
    /// the canvas's VoiceOver action.
    private func beginEditing(at index: Int) {
        caretIndex = index
        isEditing = true
        scene.setCaret(index: index)
    }

    private func isSelected(_ mode: GlyphInteraction) -> Bool {
        guard expandedSlider != .jumble else { return false }
        return interaction == mode
    }

    private func select(_ mode: GlyphInteraction) {
        store.endLiveJumble()
        // Tapping Tilt again re-levels to however the phone is being held now, which is
        // the only recovery if you started in an awkward pose.
        if mode == .tilt, interaction == .tilt { tiltSource.recalibrate() }
        interaction = mode
        withAnimation(chromeAnimation) {
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
        withAnimation(chromeAnimation) { expandedSlider = .jumble }
    }

    /// Reset lights up the moment anything has actually been applied to the letters —
    /// including a held drop, which never reaches the model and so cannot be seen by
    /// asking the composition.
    private var canReset: Bool {
        store.isJumbled || didInteract || currentAmount != 0
    }

    private func resetLetters() {
        store.endLiveJumble()
        tiltSource.recalibrate()
        store.unjumble()
        scene.reset()
        jumbleAmount = 0
        for mode in GlyphInteraction.allCases { amounts[mode] = mode.defaultAmount }
        didInteract = false
        withAnimation(chromeAnimation) { expandedSlider = nil }
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
                .accessibilityLabel(title)
                .accessibilityValue(detail)

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
                withAnimation(chromeAnimation) { expandedSlider = nil }
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

    /// Beyond this a recording is auto-stopped: the offscreen render is a frame at a
    /// time, so a very long take costs a very long export.
    private static let maximumRecordingSeconds: TimeInterval = 60

    /// Counts in, then records until YOU stop it. Touches are captured and replayed
    /// offscreen at full resolution afterwards — capturing the live view instead would
    /// be pinned to the screen's scale and would drop frames.
    private func beginVideoRecording() {
        guard !store.composition.isEmpty, recording == .idle else { return }
        isEditing = false
        recordedVideo = nil

        recordingTask = Task {
            // Count in first, so the take starts when you are ready rather than when
            // the menu item was tapped.
            for step in stride(from: 3, through: 1, by: -1) {
                recording = .countdown(step)
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { recording = .idle; return }
            }

            scene.beginTouchRecording()
            let started = Date()
            recording = .running(0)

            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard case .running = recording else { break }
                let elapsed = Date().timeIntervalSince(started)
                if elapsed >= Self.maximumRecordingSeconds {
                    await finishRecording(duration: Self.maximumRecordingSeconds)
                    return
                }
                recording = .running(elapsed)
            }
        }
    }

    private func stopVideoRecording() {
        guard case let .running(elapsed) = recording else { return }
        recordingTask?.cancel()
        recordingTask = nil
        Task { await finishRecording(duration: elapsed) }
    }

    private func finishRecording(duration: TimeInterval) async {
        let track = scene.endTouchRecording()
        // A stop tapped immediately still has to produce a playable file.
        let seconds = min(max(duration, 0.5), Self.maximumRecordingSeconds)
        recording = .rendering(0)

        do {
            let url = try await VideoExporter.export(
                composition: store.composition,
                interaction: interaction,
                interactionAmount: currentAmount,
                collisions: collisionsOn,
                touchTrack: track,
                settings: VideoExportSettings(
                    duration: seconds,
                    framesPerSecond: 30,
                    scale: 1
                ),
                progress: { fraction in recording = .rendering(fraction) }
            )
            recordedVideo = url
            recording = .idle
            isRecordingSheetUp = true
        } catch {
            recordedVideo = nil
            recording = .idle
            exportError = error.localizedDescription
        }
    }

    @ViewBuilder
    private var recordingOverlay: some View {
        switch recording {
        case .idle:
            EmptyView()

        case let .countdown(step):
            Text("\(step)")
                .font(.system(size: 84, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 132, height: 132)
                // Backed, because the count sits ON the artwork and a bare numeral
                // disappears into whatever is already there.
                .background(.black.opacity(0.45), in: .circle)
                .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1))
                .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                .id(step)
                .allowsHitTesting(false)
                .accessibilityLabel("Recording in \(step)")

        case let .running(elapsed):
            VStack {
                HStack(spacing: 10) {
                    Circle().fill(.red).frame(width: 9, height: 9)
                    Text(timecode(elapsed))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .contentTransition(.numericText())

                    Button { stopVideoRecording() } label: {
                        Label("Stop", systemImage: "stop.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.red)
                }
                .padding(.leading, 14)
                .padding(.trailing, 6)
                .padding(.vertical, 6)
                .glassEffect(.regular, in: .capsule)
                .padding(.top, 12)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .accessibilityLabel("Recording, \(Int(elapsed)) seconds. Double tap stop to finish.")

        case let .rendering(fraction):
            VStack(spacing: 10) {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .frame(width: 160)
                Text("Rendering \(Int(fraction * 100))%")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
            }
            .padding(16)
            .glassEffect(.regular, in: .rect(cornerRadius: 18))
            .allowsHitTesting(false)
        }
    }

    private func timecode(_ elapsed: TimeInterval) -> String {
        let whole = Int(elapsed)
        return String(format: "%02d:%02d", whole / 60, whole % 60)
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
        guard let image = CompositionRenderer.render(
            store.composition, time: 0, scale: 2, tilt: scene.tilt
        ) else {
            exportError = "The canvas could not be rendered. Try again after closing other apps."
            return
        }
        exportImage = image
        isExporting = true
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

/// A pill that stays lit while it is on — lock, and collision.
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
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    private var button: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 17, height: 30)
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
        // Selection is shown by tint alone, which is invisible to VoiceOver.
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var button: some View {
        Button(action: action) {
            Label(mode.label, systemImage: mode.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .labelStyle(.iconOnly)
                .frame(width: 17, height: 30)
        }
        .accessibilityLabel(mode.label)
    }
}

private struct ShuffleButton: View {
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Group {
            if isSelected { button.buttonStyle(.glassProminent) }
            else { button.buttonStyle(.glass) }
        }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var button: some View {
        Button(action: action) {
            Image(systemName: "shuffle")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 17, height: 30)
        }
        .accessibilityLabel("Shuffle letters")
    }
}
