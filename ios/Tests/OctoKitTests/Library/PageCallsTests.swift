import Foundation
import Testing
@testable import OctoKit

@Suite struct PageCallsTests {
    @Test func fileActionsSayWhatCanBeDone() throws {
        let json = """
        {"subsonic-response":{"status":"ok","libraryActions":{"enabled":true,"allowed":true,"dryRun":false,
        "actions":["remove","upgrade","restore"],"keepDays":30,"upgradeSource":"Soulseek"}}}
        """
        let actions: FileActions = try SubsonicClient.decode(Data(json.utf8), key: "libraryActions")
        #expect(actions.canRemove)
        #expect(actions.canUpgrade)
        #expect(actions.canRestore)
        #expect(!actions.canEdit)
        #expect(actions.keepDays == 30)
        #expect(actions.upgradeSource == "Soulseek")
        #expect(!FileActions(enabled: true, allowed: true, dryRun: true, actions: ["remove"]).canRemove)
        #expect(!FileActions(enabled: true, allowed: true, dryRun: false, actions: ["remove"], admin: false).canRemove)
    }

    @Test func aFolderSplitsIntoFoldersAndSongs() throws {
        let json = """
        {"subsonic-response":{"status":"ok","directory":{"id":"1","name":"Music","child":[
        {"id":"2","isDir":true,"title":"Kavinsky"},{"id":"3","isDir":true,"name":"Justice"},
        {"id":"4","isDir":false,"title":"Nightcall","duration":258}]}}}
        """
        struct Probe: Decodable {
            let folders: [String]
            let songs: [String]
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: AnyKey.self)
                let children = try c.decode([[String: AnyCodableValue]].self, forKey: AnyKey("child"))
                folders = children.filter { $0["isDir"]?.bool == true }.compactMap { $0["title"]?.text ?? $0["name"]?.text }
                songs = children.filter { $0["isDir"]?.bool != true }.compactMap { $0["title"]?.text }
            }
        }
        let probe: Probe = try SubsonicClient.decode(Data(json.utf8), key: "directory")
        #expect(probe.folders == ["Kavinsky", "Justice"])
        #expect(probe.songs == ["Nightcall"])
    }
}

/// A JSON value of any simple kind, for looking into an answer in a test.
enum AnyCodableValue: Decodable {
    case text(String), number(Double), flag(Bool), other

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) { self = .flag(b) } else if let d = try? c.decode(Double.self) { self = .number(d) }
        else if let s = try? c.decode(String.self) { self = .text(s) } else { self = .other }
    }

    var text: String? { if case .text(let s) = self { s } else { nil } }
    var bool: Bool? { if case .flag(let b) = self { b } else { nil } }
}
