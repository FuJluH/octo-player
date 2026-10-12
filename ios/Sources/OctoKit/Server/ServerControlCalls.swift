import Foundation

// The server calls the account part adds: password changes.

extension SubsonicClient {
    /// Gives a user a new password, in a form body, never in the address.
    public func changePassword(username: String, password: String) async throws {
        try await postForm("changePassword", [("username", username), ("password", password)])
    }

    /// A family member's own password, which the server checks against the current one. Every
    /// other app and device then needs the new one.
    public func changeFamilyPassword(current: String, next: String) async throws {
        try await postForm("changeFamilyPassword", [("current", current), ("next", next)])
    }
}
