//
//  RecordedVideoSheet.swift
//  Typeo
//
//  Shown after a canvas recording finishes: preview, save to Photos, share.
//

import SwiftUI
import AVKit

struct RecordedVideoSheet: View {
    let url: URL
    let aspectRatio: AspectRatio

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var outcome: PhotoSaveOutcome?
    @State private var isSaving = false
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Group {
                    if let player {
                        VideoPlayer(player: player)
                    } else {
                        RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06))
                    }
                }
                .aspectRatio(aspectRatio.ratio, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 12))
                .padding(.horizontal, 24)

                if let outcome { statusLabel(for: outcome) }

                Spacer(minLength: 0)

                VStack(spacing: 10) {
                    Button {
                        Task { await save() }
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
                }
                .padding(.horizontal, 24)
            }
            .padding(.vertical, 18)
            .navigationTitle("Recording")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showShareSheet) { ShareSheet(items: [url]) }
            .onAppear {
                let newPlayer = AVPlayer(url: url)
                newPlayer.actionAtItemEnd = .none
                NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: newPlayer.currentItem, queue: .main
                ) { _ in
                    newPlayer.seek(to: .zero)
                    newPlayer.play()
                }
                player = newPlayer
                newPlayer.play()
            }
        }
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

    private func save() async {
        isSaving = true
        outcome = await PhotoLibrarySaver.saveVideo(at: url)
        isSaving = false
    }
}
