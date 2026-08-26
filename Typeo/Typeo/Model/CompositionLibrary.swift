//
//  CompositionLibrary.swift
//  Typeo
//
//  v2 persistence. Local-only, no accounts, no network — one JSON file per
//  Composition in the app's Documents directory.
//
//  Composition has been Codable since v1, so this stores the model as-is. That is
//  the payoff for defining the model properly up front.
//

import SwiftUI
import Observation

@Observable
final class CompositionLibrary {
    private(set) var compositions: [Composition] = []

    private let directory: URL

    init(directory: URL = URL.documentsDirectory.appending(path: "Compositions")) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
    }

    // MARK: Reading

    func load() {
        // Default date strategy on BOTH sides. It encodes a Double, which round-trips
        // exactly; ISO8601 truncates sub-second precision, so a decoded Composition
        // stopped comparing equal to the one still open in the editor.
        let decoder = JSONDecoder()
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []

        compositions = urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(Composition.self, from: data)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: Writing

    /// Saves a new composition, or overwrites the stored copy if it already exists.
    @discardableResult
    func save(_ composition: Composition) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(composition) else { return false }
        let url = directory.appending(path: "\(composition.id.uuidString).json")
        guard (try? data.write(to: url, options: .atomic)) != nil else { return false }

        if let index = compositions.firstIndex(where: { $0.id == composition.id }) {
            compositions[index] = composition
        } else {
            compositions.insert(composition, at: 0)
        }
        compositions.sort { $0.createdAt > $1.createdAt }
        return true
    }

    func delete(_ composition: Composition) {
        let url = directory.appending(path: "\(composition.id.uuidString).json")
        try? FileManager.default.removeItem(at: url)
        compositions.removeAll { $0.id == composition.id }
    }

    func contains(_ composition: Composition) -> Bool {
        compositions.contains { $0.id == composition.id }
    }
}
