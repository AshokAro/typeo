//
//  VideoExporter.swift
//  Typeo
//
//  v4. Encodes offscreen frames with AVAssetWriter.
//
//  The canvas is never on screen during this: CompositionFrameRenderer draws into
//  CVPixelBuffers and they go straight to the encoder, so recording is not limited by
//  the display's refresh rate and the output is deterministic.
//

import AVFoundation
import UIKit

enum VideoExportError: LocalizedError {
    case rendererUnavailable
    case writerSetupFailed(String)
    case frameFailed(Int)
    case encodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .rendererUnavailable:        "Could not start the renderer."
        case let .writerSetupFailed(why): "Could not start the encoder: \(why)"
        case let .frameFailed(index):     "Frame \(index) could not be rendered."
        case let .encodingFailed(why):    "Encoding failed: \(why)"
        }
    }
}

nonisolated struct VideoExportSettings {
    var duration: Double = 4
    var framesPerSecond: Int32 = 30
    /// 1 renders at reference size (1080 wide). Video stays at 1 — 2160 doubles encode
    /// time for no visible gain on a phone.
    var scale: CGFloat = 1

    var frameCount: Int { Int(duration * Double(framesPerSecond)) }
}

@MainActor
enum VideoExporter {

    static func export(
        composition: Composition,
        interaction: GlyphInteraction,
        interactionAmount: Double = 0,
        touchTrack: [GlyphScene.TouchSample] = [],
        settings: VideoExportSettings = VideoExportSettings(),
        progress: @MainActor (Double) -> Void = { _ in }
    ) async throws -> URL {

        guard let frames = CompositionFrameRenderer(
            composition: composition,
            interaction: interaction,
            interactionAmount: interactionAmount,
            touchTrack: touchTrack,
            scale: settings.scale
        ) else {
            throw VideoExportError.rendererUnavailable
        }

        let url = FileManager.default.temporaryDirectory
            .appending(path: "typeo-\(UUID().uuidString).mov")

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        } catch {
            throw VideoExportError.writerSetupFailed(error.localizedDescription)
        }

        let width = Int(frames.pixelSize.width)
        let height = Int(frames.pixelSize.height)

        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
            ]
        )
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]
        )

        guard writer.canAdd(input) else {
            throw VideoExportError.writerSetupFailed("input rejected")
        }
        writer.add(input)

        guard writer.startWriting() else {
            throw VideoExportError.writerSetupFailed(
                writer.error?.localizedDescription ?? "startWriting returned false"
            )
        }
        writer.startSession(atSourceTime: .zero)

        let total = settings.frameCount
        let fps = settings.framesPerSecond

        for index in 0..<total {
            let time = Double(index) / Double(fps)
            guard let buffer = frames.frame(at: time) else {
                input.markAsFinished()
                writer.cancelWriting()
                throw VideoExportError.frameFailed(index)
            }

            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(4))
            }

            let presentation = CMTime(value: CMTimeValue(index), timescale: fps)
            if !adaptor.append(buffer, withPresentationTime: presentation) {
                input.markAsFinished()
                writer.cancelWriting()
                throw VideoExportError.encodingFailed(
                    writer.error?.localizedDescription ?? "append failed at frame \(index)"
                )
            }

            progress(Double(index + 1) / Double(total))
        }

        input.markAsFinished()
        await writer.finishWriting()

        if writer.status == .failed {
            throw VideoExportError.encodingFailed(
                writer.error?.localizedDescription ?? "unknown"
            )
        }
        return url
    }
}
