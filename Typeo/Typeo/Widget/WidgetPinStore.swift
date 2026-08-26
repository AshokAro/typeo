//
//  WidgetPinStore.swift
//  Typeo
//
//  App side of v5. Pinning renders the composition ONCE to a PNG and records it in the
//  shared manifest. The widget never re-renders: it cannot run the shader/physics
//  canvas, so it displays the finished image.
//

import SwiftUI
import Observation
import WidgetKit

@Observable
@MainActor
final class WidgetPinStore {

    private(set) var manifest: WidgetManifest

    init() {
        manifest = TypeoSharedStore.loadManifest()
    }

    var entries: [WidgetEntryPayload] { manifest.entries }

    var isSharedContainerAvailable: Bool { TypeoSharedStore.isSharedContainerAvailable }

    func isPinned(_ id: UUID) -> Bool {
        manifest.entries.contains { $0.id == id }
    }

    @discardableResult
    func pin(_ composition: Composition) -> Bool {
        guard !composition.isEmpty,
              let image = CompositionRenderer.render(composition, time: 0, scale: 1),
              let data = image.pngData()
        else { return false }

        let fileName = "\(composition.id.uuidString).png"
        guard TypeoSharedStore.writeImage(data, named: fileName) else { return false }

        let entry = WidgetEntryPayload(
            id: composition.id,
            text: composition.text,
            aspectRatio: composition.aspectRatio,
            imageFileName: fileName,
            pinnedAt: .now
        )

        var updated = manifest
        if let index = updated.entries.firstIndex(where: { $0.id == composition.id }) {
            updated.entries[index] = entry
        } else {
            updated.entries.append(entry)
        }
        updated.entries.sort { $0.pinnedAt > $1.pinnedAt }

        guard TypeoSharedStore.save(updated) else { return false }
        manifest = updated
        reloadTimelines()
        return true
    }

    func unpin(_ id: UUID) {
        var updated = manifest
        guard let index = updated.entries.firstIndex(where: { $0.id == id }) else { return }
        let removed = updated.entries.remove(at: index)
        TypeoSharedStore.removeImage(named: removed.imageFileName)
        guard TypeoSharedStore.save(updated) else { return }
        manifest = updated
        TypeoSharedStore.pruneOrphanedImages(keeping: updated)
        reloadTimelines()
    }

    func setRotationMinutes(_ minutes: Int) {
        var updated = manifest
        updated.rotationMinutes = minutes
        guard TypeoSharedStore.save(updated) else { return }
        manifest = updated
        reloadTimelines()
    }

    func image(for entry: WidgetEntryPayload) -> UIImage? {
        UIImage(contentsOfFile: TypeoSharedStore.imageURL(named: entry.imageFileName).path)
    }

    /// No-op until the widget extension exists; harmless to call.
    private func reloadTimelines() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
