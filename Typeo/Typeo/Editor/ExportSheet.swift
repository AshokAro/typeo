//
//  ExportSheet.swift
//  Typeo
//

import SwiftUI

struct ExportSheet: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    @State private var outcome: PhotoSaveOutcome?
    @State private var isSaving = false
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(.rect(cornerRadius: 10))
                    .shadow(radius: 18, y: 6)
                    .padding(.horizontal, 24)

                Text("\(Int(image.size.width * image.scale)) × \(Int(image.size.height * image.scale)) px")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)

                if let outcome {
                    statusLabel(for: outcome)
                }

                Spacer(minLength: 0)

                VStack(spacing: 10) {
                    Button {
                        Task { await saveToPhotos() }
                    } label: {
                        HStack {
                            if isSaving {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "photo.badge.plus")
                            }
                            Text(isSaving ? "Saving…" : "Save to Photos")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(isSaving)

                    Button {
                        showShareSheet = true
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.glass)
                }
                .padding(.horizontal, 24)
            }
            .padding(.top, 20)
            .padding(.bottom, 16)
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(items: [image])
            }
        }
    }

    @ViewBuilder
    private func statusLabel(for outcome: PhotoSaveOutcome) -> some View {
        switch outcome {
        case .saved:
            Label("Saved to Photos", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.subheadline)
        case .permissionDenied:
            Label("Typeo needs permission to add photos. Enable it in Settings › Typeo › Photos.",
                  systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        case let .failed(message):
            Label("Could not save: \(message)", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    private func saveToPhotos() async {
        isSaving = true
        outcome = await PhotoLibrarySaver.save(image)
        isSaving = false
    }
}
