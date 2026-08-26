//
//  WidgetPayload.swift
//  Typeo
//
//  What the widget displays. Deliberately NOT `Composition`: a widget cannot run the
//  live shader/physics canvas, so it shows a finished, already-rendered image — which
//  is what the v5 plan describes.
//
//  This type is shared by the app and (later) the widget extension. Keep it free of
//  UIKit/SpriteKit so the extension can compile it cheaply.
//

import Foundation

struct WidgetEntryPayload: Codable, Hashable, Identifiable {
    /// Matches the Composition's id, so pinning is idempotent and unpinning is exact.
    var id: UUID
    var text: String
    var aspectRatio: AspectRatio
    var imageFileName: String
    var pinnedAt: Date
}

struct WidgetManifest: Codable, Hashable {
    /// Bumped if the on-disk shape ever changes, so the extension can refuse politely
    /// rather than crash on an old file.
    var version: Int = 1
    var entries: [WidgetEntryPayload] = []
    /// How long each pinned composition stays on screen before the next one.
    var rotationMinutes: Int = 30

    static let empty = WidgetManifest()
}
