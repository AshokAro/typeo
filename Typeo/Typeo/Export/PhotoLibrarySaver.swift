//
//  PhotoLibrarySaver.swift
//  Typeo
//
//  Add-only Photos access. Requires INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription,
//  which is set in the target's build settings.
//

import Photos
import UIKit

enum PhotoSaveOutcome: Equatable {
    case saved
    case permissionDenied
    case failed(String)
}

enum PhotoLibrarySaver {

    static func save(_ image: UIImage) async -> PhotoSaveOutcome {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            return .permissionDenied
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            return .saved
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
