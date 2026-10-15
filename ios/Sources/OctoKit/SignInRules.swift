import Foundation

/// Whether the sign-in form has what the chosen way of signing in needs: a valid address, and
/// with an API key a key typed (or, when editing, a key already saved); otherwise a username
/// and a password typed (or, when editing, a password already saved).
public func signInReady(hasAddress: Bool, mode: AuthMode, username: String, password: String, apiKey: String,
                        editing: Bool, savedMode: AuthMode?) -> Bool {
    guard hasAddress else { return false }
    let savedKey = savedMode == .apiKey
    if mode == .apiKey {
        return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (editing && savedKey)
    }
    let savedPassword = savedMode != nil && !savedKey
    return !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && (!password.isEmpty || (editing && savedPassword))
}
