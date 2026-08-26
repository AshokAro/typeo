//
//  TypeoSharedStore.swift
//  Typeo
//
//  THE SEAM between the app and the (not yet created) widget extension.
//
//  A widget extension runs in its own sandbox and can only read the app's files
//  through an App Group container. App Groups require a paid Apple Developer Program
//  membership, so until that exists this falls back to the app's own Documents
//  directory: everything works inside the app, and the widget simply cannot see it yet.
//
//  WHEN THE PAID ACCOUNT ARRIVES, no code here changes. Enabling the App Group
//  capability on both targets makes `containerURL` start returning the group container
//  on its own. See TypeoWidget/README.md for the exact steps.
//

import Foundation

enum TypeoSharedStore {

    /// Must match the App Group id enabled on BOTH the app and the widget extension.
    static let appGroupIdentifier = "group.Aro.Typeo"

    /// True once the App Group capability exists. False on a free Personal Team.
    static var isSharedContainerAvailable: Bool {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) != nil
    }

    /// The App Group container when available, otherwise the app's own Documents
    /// directory. The fallback is fully functional for the app; it is simply invisible
    /// to an extension.
    static var containerURL: URL {
        if let group = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            return group
        }
        return URL.documentsDirectory
    }

    static var widgetDirectory: URL {
        let url = containerURL.appending(path: "Widget")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var imagesDirectory: URL {
        let url = widgetDirectory.appending(path: "Images")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var manifestURL: URL {
        widgetDirectory.appending(path: "manifest.json")
    }

    // MARK: Manifest

    static func loadManifest() -> WidgetManifest {
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(WidgetManifest.self, from: data),
              manifest.version == WidgetManifest.empty.version
        else { return .empty }
        return manifest
    }

    @discardableResult
    static func save(_ manifest: WidgetManifest) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(manifest) else { return false }
        return (try? data.write(to: manifestURL, options: .atomic)) != nil
    }

    // MARK: Images

    static func imageURL(named name: String) -> URL {
        imagesDirectory.appending(path: name)
    }

    @discardableResult
    static func writeImage(_ data: Data, named name: String) -> Bool {
        (try? data.write(to: imageURL(named: name), options: .atomic)) != nil
    }

    static func removeImage(named name: String) {
        try? FileManager.default.removeItem(at: imageURL(named: name))
    }

    /// Deletes images no manifest entry references any more.
    static func pruneOrphanedImages(keeping manifest: WidgetManifest) {
        let referenced = Set(manifest.entries.map(\.imageFileName))
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: imagesDirectory, includingPropertiesForKeys: nil
        )) ?? []
        for url in contents where !referenced.contains(url.lastPathComponent) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
