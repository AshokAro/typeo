//
//  BackgroundImageStore.swift
//  Typeo
//
//  A picked photo is NOT stored in the Composition. The model is saved as JSON, and
//  base64 image data would bloat every file and every undo snapshot — Composition is
//  snapshotted whole for undo. The JSON carries an id; the pixels live here.
//

import UIKit
import SpriteKit

enum BackgroundImageStore {

    static let directory: URL = {
        let url = URL.documentsDirectory.appending(path: "Backgrounds")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private static var images: [String: UIImage] = [:]
    private static var textures: [String: SKTexture] = [:]
    /// These are full-canvas bitmaps, so a handful is already megabytes.
    private static let cacheLimit = 8

    private static func trimIfNeeded() {
        if images.count > cacheLimit { images.removeAll(keepingCapacity: true) }
        if textures.count > cacheLimit { textures.removeAll(keepingCapacity: true) }
    }

    static func url(for id: String) -> URL {
        directory.appending(path: "\(id).jpg")
    }

    /// Writes a picked photo and returns its id. Downscaled first: a 48MP original
    /// would be re-scaled into the canvas on every rebuild for no visible gain.
    static func save(_ image: UIImage) -> String? {
        let id = UUID().uuidString
        let scaled = downscaled(image, maxEdge: 2160)
        guard let data = scaled.jpegData(compressionQuality: 0.9),
              (try? data.write(to: url(for: id), options: .atomic)) != nil
        else { return nil }
        images[id] = scaled
        return id
    }

    static func image(for id: String) -> UIImage? {
        if let cached = images[id] { return cached }
        // A built-in is DRAWN, not read: it has no file, so a composition using one
        // still opens on a device that has never seen it.
        if BuiltInBackgrounds.isBuiltIn(id) {
            guard let image = BuiltInBackgrounds.image(for: id) else { return nil }
            images[id] = image
            trimIfNeeded()
            return image
        }
        guard let image = UIImage(contentsOfFile: url(for: id).path) else { return nil }
        images[id] = image
        return image
    }

    /// The photo aspect-FILLED into the canvas, so the sprite maps 1:1 to the canvas
    /// and the background shader and the glass refraction need no special case.
    static func texture(for id: String, size: CGSize) -> SKTexture? {
        let key = "\(id)@\(Int(size.width))x\(Int(size.height))"
        if let cached = textures[key] { return cached }
        guard let image = image(for: id) else { return nil }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let filled = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let scale = max(size.width / image.size.width, size.height / image.size.height)
            let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(
                x: (size.width - drawn.width) / 2,
                y: (size.height - drawn.height) / 2,
                width: drawn.width,
                height: drawn.height
            ))
        }
        let texture = SKTexture(image: filled)
        textures[key] = texture
        trimIfNeeded()
        return texture
    }

    private static func downscaled(_ image: UIImage, maxEdge: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxEdge else { return image }
        let scale = maxEdge / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
