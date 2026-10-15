import Foundation
import Testing
@testable import OctoKit

/// Changing the signed-in user's password: the current one checked first, and every way it can
/// go said plainly.
@Suite struct PasswordChangeTests {
    @Test func theFormSaysWhatIsMissingBeforeAnythingIsSent() {
        #expect(passwordDraftProblem(PasswordDraft(current: "", new: "a", confirm: "a")) == "Enter your current password.")
        #expect(passwordDraftProblem(PasswordDraft(current: "old", new: "", confirm: "")) == "Enter a new password.")
        #expect(passwordDraftProblem(PasswordDraft(current: "old", new: "new", confirm: "nwe")) == "The new passwords don't match.")
        #expect(passwordDraftProblem(PasswordDraft(current: "old", new: "old", confirm: "old")) == "That's the password you have now. Choose a new one.")
        #expect(passwordDraftProblem(PasswordDraft(current: "old", new: "new", confirm: "new")) == nil)
    }

    @Test func theCurrentPasswordIsCheckedThenTheNewOneSentInTheBody() async {
        let server = FakeServer()
        server.ok()
        server.ok()
        #expect(await changeOwnPassword(server.client(), current: "old", new: "new one") == .changed)
        let check = server.requests[0]
        #expect(check.endpoint == "ping")
        #expect(check.query["t"] == MD5.hex("old" + (check.query["s"] ?? "")))
        let change = server.requests[1]
        #expect(change.method == "POST")
        #expect(change.text.replacingOccurrences(of: "+", with: "%20") == "username=winters&password=new%20one")
        #expect(!change.url.absoluteString.contains("new"))
    }

    @Test func aFamilyMemberUsesTheFamilyCall() async {
        let server = FakeServer()
        server.ok()
        server.ok()
        #expect(await changeOwnPassword(server.client(), current: "old", new: "brand new", family: true) == .changed)
        #expect(server.requests[1].endpoint == "changeFamilyPassword")
        #expect(server.requests[1].text == "current=old&next=brand%20new")
    }

    @Test func aWrongCurrentPasswordChangesNothing() async {
        let server = FakeServer()
        server.error(40)
        #expect(await changeOwnPassword(server.client(), current: "guess", new: "new") == .wrongCurrent)
        #expect(server.requestCount == 1)
    }

    @Test func anAccountThatMayNotIsToldSo() async {
        let server = FakeServer()
        server.ok()
        server.error(50)
        let result = await changeOwnPassword(server.client(), current: "old", new: "new")
        #expect(result == .notAllowed)
        #expect(passwordChangeWords(result) == "Your server doesn't let this account change its password. Ask whoever runs the server.")
    }

    @Test func aServerWithoutTheCallIsToldApartFromARefusal() async {
        let server = FakeServer()
        server.ok()
        server.enqueue(status: 501, "Not implemented")
        #expect(await changeOwnPassword(server.client(), current: "old", new: "new") == .notOffered)
        server.ok()
        server.error(10)
        #expect(await changeOwnPassword(server.client(), current: "old", new: "new") == .notOffered)
    }

    @Test func aKeyHasNoPasswordToChange() async {
        let server = FakeServer()
        #expect(await changeOwnPassword(server.client(mode: .apiKey), current: "old", new: "new") == .usesKey)
        #expect(server.requestCount == 0)
    }

    @Test func aServerOutOfReachChangesNothingAndSaysSo() async {
        let server = FakeServer()
        server.close()
        let result = await changeOwnPassword(server.client(), current: "old", new: "new")
        #expect(passwordChangeWords(result) == "Couldn't reach the server, so nothing changed. Try again in a moment.")
    }

    @Test func otherFailuresSayWhatTheServerSaid() async {
        let server = FakeServer()
        server.ok()
        server.error(0, "Disk full")
        #expect(passwordChangeWords(await changeOwnPassword(server.client(), current: "old", new: "new"))
            == "The server couldn't change the password: Disk full.")
        server.ok()
        server.enqueue(status: 503, "busy")
        #expect(passwordChangeWords(await changeOwnPassword(server.client(), current: "old", new: "new"))
            == "The server isn't answering right now, so nothing changed. Try again in a moment.")
        #expect(passwordChangeWords(.changed, family: true) == "Your password is changed. Octo uses the new one; every other app and device now needs it.")
    }

    @Test func aTokenRefusedWithCode41IsTriedAgainOnlyWhereItIsSafe() {
        let refused = SubsonicError.authNotSupported(code: 41, message: "no")
        #expect(legacyRetry(refused, mode: .token, url: URL(string: "https://music.example")!) == .retry)
        #expect(legacyRetry(refused, mode: .token, url: URL(string: "http://192.168.1.2:4533")!) == .retry)
        #expect(legacyRetry(refused, mode: .token, url: URL(string: "http://music.example")!) == .unsafe)
        #expect(legacyRetry(refused, mode: .legacyPassword, url: URL(string: "http://music.example")!) == .none)
        #expect(legacyRetry(SubsonicError.wrongCredentials("x"), mode: .token, url: URL(string: "http://music.example")!) == .none)
    }
}

/// The server's extras read from its answers.
@Suite struct ServerControlCallTests {
    @Test func extensionsAreKnownOrNot() async {
        let server = FakeServer()
        server.ok(#""openSubsonicExtensions":[{"name":"octoImports","versions":[1,2]}]"#)
        #expect(await server.client().supportsIfKnown("octoImports", version: 2) == true)
        server.enqueue(status: 404, "no")
        #expect(await server.client().supportsIfKnown("octoImports", version: 2) == false)
        server.enqueue(status: 503, "busy")
        #expect(await server.client().supportsIfKnown("octoImports", version: 2) == nil)
        server.error(40)
        #expect(await server.client().supportsIfKnown("octoImports", version: 2) == nil)
        server.error(0)
        #expect(await server.client().supportsIfKnown("octoImports", version: 2) == false)
        server.close()
        #expect(await server.client().supportsIfKnown("octoImports", version: 2) == nil)
    }

    @Test func plainWordsForEveryFailure() {
        #expect(userMessage(plainError(SubsonicError.unreachable("x", certificate: false)))
            == "Couldn't reach the server. Check the address, and that you're on the right network.")
        #expect(userMessage(plainError(SubsonicError.notSubsonic("HTTP 502 from ping", status: 502)))
            == "The server isn't answering right now. It may be restarting, so try again in a moment.")
        #expect(userMessage(plainError(SubsonicError.notSubsonic("HTTP 404 from ping", status: 404)))
            == "That address answered, but not like a music server. Check the port.")
        #expect(userMessage(plainError(SubsonicError.wrongCredentials("x"))) == "Wrong username or password.")
        #expect(userMessage(plainError(SubsonicError.authNotSupported(code: 41, message: "x")))
            == "This account can't sign in with a token. Turn on Legacy sign-in under Advanced.")
        #expect(userMessage(plainError(SubsonicError.authNotSupported(code: 42, message: "x"))) == "The server doesn't take this way of signing in.")
        #expect(userMessage(plainError(SubsonicError.notFound("x"))) == "That isn't on the server any more.")
        #expect(userMessage(plainError(SubsonicError.server(code: 0, message: "No server signed in"))) == "The server said: No server signed in")
        #expect(userMessage(plainError(CocoaError(.fileNoSuchFile))) == "Something went wrong.")
    }
}
