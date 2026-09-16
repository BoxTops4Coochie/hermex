import AVFoundation
import Foundation
import UIKit
import UniformTypeIdentifiers

enum TranscriptMediaResolvedExportKind {
    case image
    case audio
    case video
    case data
}

enum TranscriptMediaExportSupport {
    static func payload(
        for reference: TranscriptMediaReference,
        data: Data,
        resolvedKind: TranscriptMediaResolvedExportKind? = nil
    ) -> FileExportPayload {
        let descriptor = exportDescriptor(for: reference, data: data, resolvedKind: resolvedKind)
        return FileExportPayload(
            data: data,
            filename: exportFilename(for: reference, fileExtension: descriptor.fileExtension),
            contentType: descriptor.contentType,
            isImage: descriptor.kind == .image,
            isVideo: descriptor.kind == .video
        )
    }

    private static func exportDescriptor(
        for reference: TranscriptMediaReference,
        data: Data,
        resolvedKind: TranscriptMediaResolvedExportKind?
    ) -> TranscriptMediaExportDescriptor {
        if let fileExtension = reference.exportFileExtension,
           let contentType = UTType(filenameExtension: fileExtension) {
            return TranscriptMediaExportDescriptor(
                kind: exportKind(for: contentType),
                contentType: contentType,
                fileExtension: fileExtension
            )
        }

        if resolvedKind == .image || UIImage(data: data) != nil {
            // Reached only when the reference carries no usable extension, so
            // identify the container from the bytes: exporting JPEG/WebP/HEIC
            // bytes under a .png name makes Photos/Files refuse or mislabel the
            // document.
            let sniffedType = imageType(for: data) ?? .png
            return TranscriptMediaExportDescriptor(
                kind: .image,
                contentType: sniffedType,
                fileExtension: sniffedType.preferredFilenameExtension ?? "png"
            )
        }

        if resolvedKind == .audio || isAudioData(data) {
            let audioType = audioType(from: data) ?? (UTType(filenameExtension: "m4a") ?? .audio, "m4a")
            return TranscriptMediaExportDescriptor(
                kind: .audio,
                contentType: audioType.contentType,
                fileExtension: audioType.fileExtension
            )
        }

        if resolvedKind == .data {
            return TranscriptMediaExportDescriptor(kind: .data, contentType: .data, fileExtension: "bin")
        }

        // Non-image payloads keep the guessed .mp4 container: the transcript
        // only routes here for references previewed as video, and movie
        // containers (ftyp/MOV) are not sniffed beyond that.
        return TranscriptMediaExportDescriptor(kind: .video, contentType: .mpeg4Movie, fileExtension: "mp4")
    }

    private static func exportFilename(for reference: TranscriptMediaReference, fileExtension: String) -> String {
        let baseName = reference.exportBaseName
        guard URL(fileURLWithPath: baseName).pathExtension.isEmpty else {
            return baseName
        }

        return "\(baseName).\(fileExtension)"
    }

    private static func exportKind(for contentType: UTType) -> TranscriptMediaResolvedExportKind {
        if contentType.conforms(to: .image) {
            return .image
        }

        if contentType.conforms(to: .audio) {
            return .audio
        }

        if contentType.conforms(to: .movie) || contentType.conforms(to: .video) {
            return .video
        }

        return .data
    }

    /// Identifies an image container from the bytes' magic numbers. Used when
    /// the reference carries no file extension, so the export document names the
    /// real format instead of guessing PNG for everything UIImage can decode.
    static func imageType(for data: Data) -> UTType? {
        if data.starts(with: [0xFF, 0xD8, 0xFF]) {
            return .jpeg
        }

        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return .png
        }

        if data.starts(with: Array("GIF8".utf8)) {
            return .gif
        }

        if data.starts(with: Array("RIFF".utf8)),
           bytes(data, at: 8, count: 4) == Array("WEBP".utf8) {
            return .webP
        }

        if bytes(data, at: 4, count: 4) == Array("ftyp".utf8),
           let heifType = heifType(forMajorBrand: bytes(data, at: 8, count: 4)) {
            return heifType
        }

        return nil
    }

    private static func heifType(forMajorBrand brand: [UInt8]) -> UTType? {
        guard brand.count == 4, let brandName = String(bytes: brand, encoding: .ascii) else {
            return nil
        }

        switch brandName {
        case "heic", "heix", "heim", "heis", "hevc", "hevx":
            return .heic
        case "mif1", "msf1":
            return .heif
        default:
            return nil
        }
    }

    private static func bytes(_ data: Data, at offset: Int, count: Int) -> [UInt8] {
        guard data.count >= offset + count else { return [] }
        return Array(data[data.startIndex + offset ..< data.startIndex + offset + count])
    }

    private static func isAudioData(_ data: Data) -> Bool {
        (try? AVAudioPlayer(data: data)) != nil
    }

    private static func audioType(from data: Data) -> (contentType: UTType, fileExtension: String)? {
        if data.starts(with: Array("RIFF".utf8)), data.dropFirst(8).starts(with: Array("WAVE".utf8)) {
            return (.wav, "wav")
        }

        if data.starts(with: [0x49, 0x44, 0x33]) {
            return (.mp3, "mp3")
        }

        if data.count >= 2 {
            let bytes = Array(data.prefix(2))
            if bytes[0] == 0xFF, (bytes[1] & 0xE0) == 0xE0 {
                return (.mp3, "mp3")
            }
        }

        if data.starts(with: Array("caff".utf8)) {
            return (UTType(filenameExtension: "caf") ?? .audio, "caf")
        }

        return nil
    }
}

private struct TranscriptMediaExportDescriptor {
    let kind: TranscriptMediaResolvedExportKind
    let contentType: UTType
    let fileExtension: String
}

extension TranscriptMediaReference {
    var exportBaseName: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "Hermes Media") : trimmed
    }

    var exportFileExtension: String? {
        let fileExtension: String
        switch source {
        case let .remoteURL(url):
            fileExtension = url.pathExtension
        case let .localPath(path):
            fileExtension = URL(fileURLWithPath: path).pathExtension
        }

        let normalized = fileExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }
}
