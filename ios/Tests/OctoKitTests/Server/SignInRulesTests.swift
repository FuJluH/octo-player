import Foundation
import Testing
@testable import OctoKit

/// The sign-in form's rules: when it is ready, which header rows count, how the home address is
/// read, and what a kept server says about API keys.
@Suite struct SignInRulesTests {
    private let main = URL(string: "https://music.example.com")!

    @Test func aPasswordSignInNeedsAUsernameAndAPassword() {
        #expect(signInReady(hasAddress: true, mode: .token, username: "me", password: "pw", apiKey: "", editing: false, savedMode: nil))
        #expect(!signInReady(hasAddress: false, mode: .token, username: "me", password: "pw", apiKey: "", editing: false, savedMode: nil))
        #expect(!signInReady(hasAddress: true, mode: .token, username: " ", password: "pw", apiKey: "", editing: false, savedMode: nil))
        #expect(!signInReady(hasAddress: true, mode: .token, username: "me", password: "", apiKey: "", editing: false, savedMode: nil))
    }

    @Test func editingFallsBackOnlyOnASecretOfTheSameKind() {
        // A saved password serves token and legacy sign-in.
        #expect(signInReady(hasAddress: true, mode: .token, username: "me", password: "", apiKey: "", editing: true, savedMode: .token))
        #expect(signInReady(hasAddress: true, mode: .legacyPassword, username: "me", password: "", apiKey: "", editing: true, savedMode: .token))
        // A saved key is no password.
        #expect(!signInReady(hasAddress: true, mode: .token, username: "me", password: "", apiKey: "", editing: true, savedMode: .apiKey))
        // A saved password is no key.
        #expect(!signInReady(hasAddress: true, mode: .apiKey, username: "", password: "", apiKey: "", editing: true, savedMode: .token))
        #expect(signInReady(hasAddress: true, mode: .apiKey, username: "", password: "", apiKey: "", editing: true, savedMode: .apiKey))
        // Signing in again relies on nothing saved.
        #expect(!signInReady(hasAddress: true, mode: .token, username: "me", password: "", apiKey: "", editing: false, savedMode: .token))
    }

    @Test func aKeyOfOnlySpacesIsNoKey() {
        #expect(!signInReady(hasAddress: true, mode: .apiKey, username: "", password: "", apiKey: "  ", editing: false, savedMode: nil))
        #expect(signInReady(hasAddress: true, mode: .apiKey, username: "", password: "", apiKey: " key ", editing: false, savedMode: nil))
    }

    @Test func headerRowsAreTrimmedAndEmptyOnesIgnored() {
        let rows = HeaderRules.rows([
            .init(name: " X-Token ", value: " abc ", saved: false),
            .init(name: "  ", value: " ", saved: false),
            .init(name: "X-Saved", value: "", saved: true),
        ])
        #expect(rows == [.init(name: "X-Token", value: "abc", saved: false), .init(name: "X-Saved", value: "", saved: true)])
    }

    @Test func aBadHeaderRowStopsTheSave() {
        #expect(HeaderRules.rows([.init(name: "X Token", value: "abc", saved: false)]) == nil)
        #expect(HeaderRules.rows([.init(name: "X-Token", value: "", saved: false)]) == nil)
        #expect(HeaderRules.rows([.init(name: "", value: "abc", saved: false)]) == nil)
        // A typed value is checked even on a saved header.
        #expect(HeaderRules.rows([.init(name: "X-Saved", value: "caf\u{E9}", saved: true)]) == nil)
        #expect(HeaderRules.rows([.init(name: "X-Tab", value: "a\tb", saved: false)]) != nil)
    }

    @Test func aHomeAddressWithNoSchemeIsHttp() {
        #expect(ServerAddress.home("music.example.org", main: main) == .address(URL(string: "http://music.example.org")!))
        #expect(ServerAddress.home("192.168.50.21:5274/", main: main) == .address(URL(string: "http://192.168.50.21:5274")!))
        #expect(ServerAddress.home("https://home.example.com/rest", main: main) == .address(URL(string: "https://home.example.com")!))
    }

    @Test func aBlankOrRepeatedHomeAddressIsNone() {
        #expect(ServerAddress.home("  ", main: main) == ServerAddress.HomeReading.none)
        #expect(ServerAddress.home("https://Music.example.com/", main: main) == ServerAddress.HomeReading.none)
        #expect(ServerAddress.home("http://", main: main) == .unreadable)
    }

    @Test func takingApiKeysComesFromTheSavedExtensions() {
        let address = URL(string: "https://music.example.com/")!
        #expect(StoredServer(address: address, username: "me", extensions: ["apiKeyAuthentication:1"]).takesApiKeys)
        #expect(!StoredServer(address: address, username: "me", extensions: ["apiKeyAuthenticationX"]).takesApiKeys)
        #expect(!StoredServer(address: address, username: "me", extensions: []).takesApiKeys)
    }

    @Test func aServerSavedBeforeCertificateNamesStillReads() throws {
        let saved = #"[{"id":"a","address":"https://music.example.com","username":"me","mode":"token","headerNames":[],"hasClientCertificate":true,"isOcto":false,"extensions":[],"signedOut":false}]"#
        let servers = try JSONDecoder().decode([StoredServer].self, from: Data(saved.utf8))
        #expect(servers.first?.hasClientCertificate == true)
        #expect(servers.first?.clientCertificateName == nil)
        var named = try #require(servers.first)
        named.clientCertificateName = "phone.p12"
        let again = try JSONDecoder().decode(StoredServer.self, from: JSONEncoder().encode(named))
        #expect(again.clientCertificateName == "phone.p12")
    }
}
