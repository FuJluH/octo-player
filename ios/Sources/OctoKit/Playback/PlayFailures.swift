import Foundation

/// Why a song would not play, in the words every app shows.
public enum PlayFailure: String, Sendable, CaseIterable {
    case missing = "That song isn't on the server any more."
    case refused = "The server wouldn't send that song."
    case unreachable = "Couldn't reach the server to play that song."
    case unsupported = "Octo can't play that kind of file."
    case damaged = "That song's file is damaged."
    case device = "The sound device stopped working. Pick another output."
    case other = "That song couldn't play."

    public var words: String { rawValue }
}

/// The one line shown when a song is passed over, or when it was the last that could have played.
public func skippedLine(_ title: String, _ why: String) -> String { "Skipped \(title). \(why)" }

public func stoppedLine(_ title: String, _ why: String) -> String { "Couldn't play \(title). \(why)" }

/// What kind of error stopped a song, as the player reports it.
public enum PlayErrorCode: Sendable, Equatable {
    case badHttpStatus
    case fileNotFound
    case networkConnectionFailed
    case networkConnectionTimeout
    case timeout
    case decodingFormatUnsupported
    case decodingFormatExceedsCapabilities
    case parsingContainerUnsupported
    case parsingManifestUnsupported
    case parsingContainerMalformed
    case parsingManifestMalformed
    case decodingFailed
    case audioTrackInitFailed
    case audioTrackWriteFailed
    /// Reading failed some other way, such as a load refused before the server was asked.
    case ioUnspecified
    case unspecified
}

/// A song that could not play: what kind of error, and for an HTTP answer its status.
public struct PlayError: Error, Sendable, Equatable {
    public var code: PlayErrorCode
    public var httpStatus: Int?
    /// Said in the log, never shown.
    public var detail: String

    public init(_ code: PlayErrorCode, httpStatus: Int? = nil, detail: String = "") {
        self.code = code
        self.httpStatus = httpStatus
        self.detail = detail
    }
}

/// Which of the shared reasons an error is, from its kind and, for an HTTP answer, its status.
/// A song found online (`outside`) was never on the server, so a "not found" for it is the
/// server not sending it.
public func playFailureOf(_ code: PlayErrorCode, httpStatus: Int? = nil, outside: Bool = false) -> PlayFailure {
    switch code {
    case .badHttpStatus:
        (httpStatus == 404 || httpStatus == 410) && !outside ? .missing : .refused
    case .fileNotFound: .missing
    case .networkConnectionFailed, .networkConnectionTimeout, .timeout: .unreachable
    case .decodingFormatUnsupported, .decodingFormatExceedsCapabilities, .parsingContainerUnsupported, .parsingManifestUnsupported:
        .unsupported
    case .parsingContainerMalformed, .parsingManifestMalformed, .decodingFailed: .damaged
    case .audioTrackInitFailed, .audioTrackWriteFailed: .device
    case .ioUnspecified, .unspecified: .other
    }
}

public func playFailureOf(_ error: PlayError, outside: Bool = false) -> PlayFailure {
    playFailureOf(error.code, httpStatus: error.httpStatus, outside: outside)
}
