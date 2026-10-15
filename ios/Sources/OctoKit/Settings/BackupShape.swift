import Foundation

/// The kind of value each field of a backup holds. A file is checked against it before it is
/// read: a field of the wrong kind anywhere refuses the whole file, a null takes the field's
/// default, and a choice this app does not know is left for its reader to take the default.
indirect enum BackupShape: Sendable {
    case text
    case flag
    /// A whole number that fits in 32 bits. Written in quotes it still reads.
    case int
    /// A whole number that fits in 64 bits. Written in quotes it still reads.
    case long
    /// A number that fits a 32-bit float. Written in quotes it still reads.
    case decimal
    /// A choice by its name. Any name reads.
    case choice
    case list(BackupShape)
    /// An object with any keys, each value of one shape.
    case map(BackupShape)
    case object([BackupField])

    /// A value that does not fit its field.
    struct Mismatch: Error {}

    /// The value as its field holds it: numbers written in quotes as numbers, nulls in fields
    /// with a default and keys no field has left out, and a key written twice kept once, with
    /// its last value.
    func normalized(_ value: OrderedJSON) throws -> OrderedJSON {
        switch (self, value) {
        case (.text, .string), (.flag, .bool), (.choice, .string):
            return value
        case (.int, _), (.long, _):
            guard let number = Self.whole(value) else { throw Mismatch() }
            if case .int = self, number < Int64(Int32.min) || number > Int64(Int32.max) { throw Mismatch() }
            return .int(number)
        case (.decimal, _):
            guard let number = Self.decimal(value), Float(number).isFinite else { throw Mismatch() }
            return .double(number)
        case (.list(let item), .array(let items)):
            return .array(try items.map { try item.normalized($0) })
        case (.map(let item), .object(let pairs)):
            var out: [(String, OrderedJSON)] = []
            for (key, entry) in pairs { Self.put(&out, key, try item.normalized(entry)) }
            return .object(out)
        case (.object(let fields), .object(let pairs)):
            var out: [(String, OrderedJSON)] = []
            for (key, entry) in pairs {
                guard let field = fields.first(where: { $0.name == key }) else { continue }
                if case .null = entry {
                    switch field.need {
                    case .required: throw Mismatch()
                    case .defaulted: Self.put(&out, key, nil)
                    case .nullable: Self.put(&out, key, .null)
                    }
                } else {
                    Self.put(&out, key, try field.shape.normalized(entry))
                }
            }
            for field in fields where field.need == .required && !out.contains(where: { $0.0 == field.name }) { throw Mismatch() }
            return .object(out)
        default:
            throw Mismatch()
        }
    }

    private static func put(_ pairs: inout [(String, OrderedJSON)], _ key: String, _ value: OrderedJSON?) {
        pairs.removeAll { $0.0 == key }
        if let value { pairs.append((key, value)) }
    }

    /// A whole number, or one written in quotes with only digits and an optional minus sign.
    private static func whole(_ value: OrderedJSON) -> Int64? {
        switch value {
        case .int(let number): return number
        case .string(let text):
            guard !text.hasPrefix("+") else { return nil }
            return Int64(text)
        default: return nil
        }
    }

    private static func decimal(_ value: OrderedJSON) -> Double? {
        switch value {
        case .int(let number): return Double(number)
        case .double(let number): return number
        case .string(let text): return Double(text.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }
}

/// One field of an object in a backup.
struct BackupField: Sendable {
    enum Need: Sendable {
        /// Must be there, and not null.
        case required
        /// Missing or null takes the field's default.
        case defaulted
        /// Null is kept, as no value.
        case nullable
    }

    var name: String
    var shape: BackupShape
    var need: Need

    init(_ name: String, _ shape: BackupShape, _ need: Need = .defaulted) {
        self.name = name
        self.shape = shape
        self.need = need
    }
}

extension BackupShape {
    private static func fields(_ fields: BackupField...) -> BackupShape { .object(fields) }

    static let songKey = fields(
        BackupField("relinkKey", .text), BackupField("title", .text), BackupField("artist", .text), BackupField("album", .text),
        BackupField("durationMs", .long)
    )

    static let heldKey = fields(BackupField("relinkKey", .text), BackupField("name", .text), BackupField("artist", .text))

    static let eqFilter = fields(
        BackupField("type", .choice), BackupField("frequency", .decimal, .required), BackupField("gainDb", .decimal, .required),
        BackupField("q", .decimal), BackupField("enabled", .flag)
    )

    static let soundSettings = fields(
        BackupField("eqEnabled", .flag), BackupField("mode", .choice), BackupField("graphicGains", .list(.decimal)),
        BackupField("filters", .list(eqFilter)), BackupField("preset", .text, .nullable), BackupField("preampDb", .decimal),
        BackupField("autoPreamp", .flag),
        BackupField("correction", fields(
            BackupField("name", .text, .required), BackupField("source", .text, .required),
            BackupField("preampDb", .decimal, .required), BackupField("filters", .list(eqFilter), .required)
        ), .nullable),
        BackupField("replayGain", .choice), BackupField("replayGainPreampDb", .decimal), BackupField("replayGainFallbackDb", .decimal),
        BackupField("preventClipping", .flag), BackupField("limiter", .flag), BackupField("balance", .decimal), BackupField("mono", .flag),
        BackupField("crossfeed", fields(
            BackupField("on", .flag), BackupField("preset", .choice), BackupField("cutHz", .int), BackupField("feedDb", .decimal)
        ))
    )

    static let player = fields(
        BackupField("liveBackground", .flag),
        BackupField("background", fields(
            BackupField("mode", .choice), BackupField("brightnessCap", .int), BackupField("saturation", .int),
            BackupField("contrast", .decimal), BackupField("useBpm", .flag), BackupField("fps", .int), BackupField("speed", .int)
        )),
        BackupField("crossfade", .flag), BackupField("crossfadeSeconds", .int), BackupField("crossfadeCurve", .choice),
        BackupField("smartTransitions", .flag),
        BackupField("filterSweeps", .flag), BackupField("matchTempo", .flag), BackupField("lyricsOnline", .flag),
        BackupField("speed", .decimal), BackupField("keepPitch", .flag), BackupField("pitchSemitones", .int),
        BackupField("skipSilence", .flag), BackupField("autoplay", .flag), BackupField("radioDiscovery", .choice),
        BackupField("radioAdventure", .choice), BackupField("radioVariety", .choice), BackupField("radioFavorites", .flag),
        BackupField("resumeWired", .flag), BackupField("resumeBluetooth", .flag), BackupField("resumeAlways", .flag),
        BackupField("ambient", fields(
            BackupField("strength", .choice), BackupField("home", .flag), BackupField("library", .flag), BackupField("search", .flag),
            BackupField("settings", .flag), BackupField("bar", .flag), BackupField("pageArtwork", .flag)
        )),
        BackupField("reduceMotion", .flag), BackupField("castRenderers", .flag), BackupField("castKeepPlaying", .flag),
        BackupField("libraryOnly", .flag), BackupField("accent", .choice), BackupField("glassTint", .flag),
        BackupField("animatedArt", .choice)
    )

    static let streaming = fields(
        BackupField("copies", .choice), BackupField("wifi", .choice), BackupField("mobile", .choice), BackupField("startAfter", .choice)
    )

    static let lyricsLook = fields(
        BackupField("style", .choice), BackupField("emphasis", .int), BackupField("glow", .int), BackupField("lift", .int),
        BackupField("speed", .int), BackupField("inactiveScale", .int), BackupField("fade", .int), BackupField("cascade", .int),
        BackupField("keepCompleted", .flag), BackupField("arc", .flag), BackupField("bloomFast", .flag)
    )

    static let lyrics = fields(
        BackupField("keepScreenOn", .flag),
        BackupField("offsets", .list(fields(BackupField("song", songKey, .required), BackupField("offsetMs", .long, .required)))),
        BackupField("look", lyricsLook, .nullable),
        BackupField("outputOffsets", .map(.long))
    )

    static let offline = fields(
        BackupField("cacheSize", .choice), BackupField("prefetchWifi", .int), BackupField("prefetchMobile", .int),
        BackupField("downloadQuality", .choice), BackupField("wifiOnly", .flag), BackupField("streamOnWifi", .flag),
        BackupField("keepLiked", .flag), BackupField("keptPlaylists", .list(.text))
    )

    /// A whole backup file.
    static let backup = fields(
        BackupField("kind", .text), BackupField("version", .int), BackupField("createdAt", .long),
        BackupField("player", player, .nullable),
        BackupField("streaming", streaming, .nullable),
        BackupField("sound", fields(BackupField("perOutput", .flag), BackupField("profiles", .map(soundSettings))), .nullable),
        BackupField("presets", .list(fields(BackupField("name", .text, .required), BackupField("gains", .list(.decimal), .required)))),
        BackupField("library", fields(
            BackupField("excludedFolders", .list(.text)), BackupField("syncQueue", .flag), BackupField("newPlaylistsOnServer", .flag)
        ), .nullable),
        BackupField("server", fields(BackupField("address", .text, .required), BackupField("username", .text, .required)), .nullable),
        BackupField("playlists", .list(fields(BackupField("name", .text, .required), BackupField("songs", .list(songKey))))),
        BackupField("likes", .list(songKey)),
        BackupField("ratings", .list(fields(BackupField("song", songKey, .required), BackupField("rating", .int, .required)))),
        BackupField("favouriteAlbums", .list(heldKey)),
        BackupField("favouriteArtists", .list(heldKey)),
        BackupField("pins", .list(fields(BackupField("kind", .text, .required), BackupField("item", heldKey, .required)))),
        BackupField("lyrics", lyrics, .nullable),
        BackupField("offline", offline, .nullable),
        BackupField("listenBrainz", fields(
            BackupField("enabled", .flag), BackupField("sendPlays", .choice), BackupField("nowPlaying", .flag)
        ), .nullable),
        BackupField("homeSections", .text, .nullable),
        BackupField("sortOrders", .map(.text)),
        BackupField("keptStations", .list(liveStation))
    )

    /// A kept live radio station.
    static let liveStation = fields(
        BackupField("uuid", .text, .required), BackupField("name", .text), BackupField("streamUrl", .text, .required),
        BackupField("favicon", .text), BackupField("codec", .text), BackupField("bitrate", .int), BackupField("hls", .flag),
        BackupField("country", .text), BackupField("countryCode", .text), BackupField("state", .text),
        BackupField("tags", .list(.text)), BackupField("clicks", .int)
    )
}
