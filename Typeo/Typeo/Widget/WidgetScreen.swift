//
//  WidgetScreen.swift
//  Typeo
//
//  v5, in-app half. Pins compositions and previews exactly what the widget will show,
//  at real widget dimensions, using the SAME view the extension will use.
//
//  This exists so v5 is testable before the widget extension can be created — that
//  needs an App Group, which needs a paid Apple Developer Program membership.
//

import SwiftUI

struct WidgetScreen: View {
    let library: CompositionLibrary
    let pins: WidgetPinStore

    /// Approximate iPhone widget sizes in points.
    private enum WidgetSize: String, CaseIterable, Identifiable {
        case small, medium, large
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        var dimensions: CGSize {
            switch self {
            case .small:  CGSize(width: 158, height: 158)
            case .medium: CGSize(width: 338, height: 158)
            case .large:  CGSize(width: 338, height: 354)
            }
        }
    }

    @State private var previewSize: WidgetSize = .small
    @State private var previewIndex = 0
    @State private var showPicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    statusCard
                    previewCard
                    rotationCard
                    pinnedList
                }
                .padding(16)
            }
            .background(Color.black)
            .navigationTitle("Widget")
            // The picker existed and was never presented: tapping the preview set
            // showPicker and nothing was listening, so choosing what the widget shows
            // did nothing at all.
            .sheet(isPresented: $showPicker) {
                WidgetPickerSheet(library: library, pins: pins)
            }
        }
    }

    // MARK: Status

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                pins.isSharedContainerAvailable ? "Ready for the widget" : "Widget not installable yet",
                systemImage: pins.isSharedContainerAvailable ? "checkmark.circle.fill" : "clock.badge.exclamationmark"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(pins.isSharedContainerAvailable ? .green : .orange)

            Text(pins.isSharedContainerAvailable
                 ? "The App Group is active, so the home-screen widget can read what you pin here."
                 : "Pinning works and everything below is live. The home-screen widget itself needs an App Group, which requires a paid Apple Developer Program membership. Nothing here changes when you add it — the widget just starts seeing these.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.05), in: .rect(cornerRadius: 12))
    }

    // MARK: Preview

    private var previewCard: some View {
        VStack(spacing: 14) {
            Picker("Size", selection: $previewSize) {
                ForEach(WidgetSize.allCases) { size in
                    Text(size.label).tag(size)
                }
            }
            .pickerStyle(.segmented)

            let entry = currentEntry
            // NOT a button. Wrapping the preview in one gave it a hit area the size of
            // the aspect-filled image, which overflows the frame and covered the size
            // picker above — so choosing Large opened the composition sheet instead.
            WidgetCompositionView(entry: entry, image: entry.flatMap { pins.image(for: $0) })
                .frame(width: previewSize.dimensions.width, height: previewSize.dimensions.height)
                .clipShape(.rect(cornerRadius: 22))
                .shadow(radius: 12, y: 5)

            if pins.entries.count > 1 {
                HStack(spacing: 12) {
                    Button {
                        previewIndex = max(0, previewIndex - 1)
                    } label: { Image(systemName: "chevron.left") }
                        .disabled(previewIndex == 0)

                    Text("\(previewIndex + 1) of \(pins.entries.count)")
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Button {
                        previewIndex = min(pins.entries.count - 1, previewIndex + 1)
                    } label: { Image(systemName: "chevron.right") }
                        .disabled(previewIndex >= pins.entries.count - 1)
                }
                .buttonStyle(.glass)
            }

            Button {
                showPicker = true
            } label: {
                Label("Choose compositions", systemImage: "square.grid.2x2")
                    .font(.subheadline)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 14)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Choose what the widget shows")
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Color.white.opacity(0.05), in: .rect(cornerRadius: 12))
    }

    private var currentEntry: WidgetEntryPayload? {
        guard !pins.entries.isEmpty else { return nil }
        return pins.entries[min(previewIndex, pins.entries.count - 1)]
    }

    // MARK: Rotation

    private var rotationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rotate every")
                .font(.subheadline.weight(.semibold))
            Picker("Rotation", selection: Binding(
                get: { pins.manifest.rotationMinutes },
                set: { pins.setRotationMinutes($0) }
            )) {
                Text("15 min").tag(15)
                Text("30 min").tag(30)
                Text("1 hour").tag(60)
            }
            .pickerStyle(.segmented)

            Text("The widget shows one pinned composition at a time and moves to the next on this schedule. It cannot animate — widgets can't run the shader or physics canvas.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.05), in: .rect(cornerRadius: 12))
    }

    // MARK: Pinned list

    private var pinnedList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Pinned")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(pins.entries.count)")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if pins.entries.isEmpty {
                Text("Nothing chosen yet. Use Choose compositions above to pick some.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(pins.entries) { entry in
                    HStack(spacing: 12) {
                        WidgetCompositionView(entry: entry, image: pins.image(for: entry))
                            .frame(width: 48, height: 48)
                            .clipShape(.rect(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.text.isEmpty ? "Untitled" : entry.text)
                                .font(.subheadline)
                                .lineLimit(1)
                            Text(entry.aspectRatio.label)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            pins.unpin(entry.id)
                            previewIndex = 0
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Unpin \(entry.text)")
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.05), in: .rect(cornerRadius: 12))
    }
}
