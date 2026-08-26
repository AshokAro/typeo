//
//  RecordSheet.swift
//  Typeo
//
//  v4 recording UI. Records the animation that is already on the canvas — the animated
//  shader plus whichever tap-and-hold interaction is selected, run automatically.
//

import SwiftUI
import AVKit

struct RecordSheet: View {
    let composition: Composition
    let interaction: GlyphInteraction

    @Environment(\.dismiss) private var dismiss

    @State private var settings = VideoExportSettings()
    @State private var isRecording = false
    @State private var progress: Double = 0
    @State private var result: URL?
    @State private var player: AVPlayer?
    @State private var errorMessage: String?
    @State private var outcome: PhotoSaveOutcome?
    @State private var isSaving = false
    @State private var showShareSheet = false

    private let durations: [Double] = [2, 4, 6]

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                preview

                if result == nil {
                    durationPicker
                    if !willAnimate {
                        Label(
                            "Nothing is animating. Pick an effect in Style, or a Float or Drop mode, and the recording will have something to show.",
                            systemImage: "info.circle"
                        )
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    }
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                if let outcome { statusLabel(for: outcome) }

                Spacer(minLength: 0)

                actions
            }
            .padding(.top, 18)
            .padding(.bottom, 16)
            .navigationTitle(result == nil ? "Record" : "Recorded")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.disabled(isRecording)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let result { ShareSheet(items: [result]) }
            }
        }
    }

    // MARK: Pieces

    @ViewBuilder
    private var preview: some View {
        if let player {
            VideoPlayer(player: player)
                .aspectRatio(composition.aspectRatio.ratio, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 10))
                .padding(.horizontal, 24)
                .onAppear {
                    player.actionAtItemEnd = .none
                    NotificationCenter.default.addObserver(
                        forName: .AVPlayerItemDidPlayToEndTime,
                        object: player.currentItem,
                        queue: .main
                    ) { _ in
                        player.seek(to: .zero)
                        player.play()
                    }
                    player.play()
                }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06))
                if isRecording {
                    VStack(spacing: 12) {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .frame(width: 160)
                        Text("\(Int(progress * 100))%")
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Image(systemName: "video")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            .aspectRatio(composition.aspectRatio.ratio, contentMode: .fit)
            .padding(.horizontal, 24)
        }
    }

    private var durationPicker: some View {
        Picker("Duration", selection: $settings.duration) {
            ForEach(durations, id: \.self) { seconds in
                Text("\(Int(seconds))s").tag(seconds)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 24)
        .disabled(isRecording)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if result == nil {
                Button {
                    Task { await record() }
                } label: {
                    HStack {
                        if isRecording { ProgressView().controlSize(.small) }
                        else { Image(systemName: "record.circle") }
                        Text(isRecording ? "Recording…" : "Record")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.glassProminent)
                .disabled(isRecording)
            } else {
                Button {
                    Task { await saveToPhotos() }
                } label: {
                    HStack {
                        if isSaving { ProgressView().controlSize(.small) }
                        else { Image(systemName: "photo.badge.plus") }
                        Text(isSaving ? "Saving…" : "Save to Photos")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.glassProminent)
                .disabled(isSaving)

                Button { showShareSheet = true } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.glass)

                Button("Record again") {
                    player = nil
                    result = nil
                    outcome = nil
                    progress = 0
                }
                .font(.system(size: 15))
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 24)
    }

    private var willAnimate: Bool {
        composition.globalShader.kind.isAnimated || interaction != .none
    }

    @ViewBuilder
    private func statusLabel(for outcome: PhotoSaveOutcome) -> some View {
        switch outcome {
        case .saved:
            Label("Saved to Photos", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green).font(.system(size: 15, weight: .medium))
        case .permissionDenied:
            Label("Typeo needs permission to add videos. Enable it in Settings › Typeo › Photos.",
                  systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange).font(.system(size: 14))
                .multilineTextAlignment(.center).padding(.horizontal, 24)
        case let .failed(message):
            Label("Could not save: \(message)", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red).font(.system(size: 14))
                .multilineTextAlignment(.center).padding(.horizontal, 24)
        }
    }

    // MARK: Actions

    private func record() async {
        isRecording = true
        errorMessage = nil
        progress = 0
        do {
            let url = try await VideoExporter.export(
                composition: composition,
                interaction: interaction,
                settings: settings
            ) { value in
                progress = value
            }
            result = url
            player = AVPlayer(url: url)
        } catch {
            errorMessage = error.localizedDescription
        }
        isRecording = false
    }

    private func saveToPhotos() async {
        guard let result else { return }
        isSaving = true
        outcome = await PhotoLibrarySaver.saveVideo(at: result)
        isSaving = false
    }
}
