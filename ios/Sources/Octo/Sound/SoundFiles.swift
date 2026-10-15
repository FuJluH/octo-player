import OctoKit
import SwiftUI
import UniformTypeIdentifiers

/// A text file the listener saves through the Files app.
struct SoundTextFile: FileDocument {
    static let readableContentTypes: [UTType] = [.plainText]

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        text = configuration.file.regularFileContents.map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// Reading a correction file the listener picked.
enum SoundFiles {
    /// The largest file read; real ones are a few hundred bytes.
    static let largestFile = 256 * 1_024

    /// A headphone correction from a picked file, or nothing when it cannot be read or has no
    /// filters Octo can use. It is named after the file.
    static func readCorrection(_ url: URL) -> HeadphoneCorrection? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: largestFile) else { return nil }
        let name = (try? url.resourceValues(forKeys: [.nameKey]).name) ?? url.lastPathComponent
        return ParametricEqFile.correction(fileName: name, text: String(decoding: data, as: UTF8.self))
    }
}
