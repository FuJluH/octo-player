import Foundation

// What the app says when another kept server is put in use.

/// The notice once another server is in use, and plainly when music was stopped for it. Nil when
/// nothing was in use before.
public func serverSwitchNotice(to: String, from: String?, stoppedMusic: Bool) -> String? {
    guard let from else { return nil }
    if stoppedMusic { return "Now on \(to). The music from \(from) stopped, and its queue is kept for when you come back." }
    return "Now on \(to)."
}

/// What a failed switch says: the server's name, then why.
public func serverSwitchFailedWords(_ name: String, why: String) -> String { "Couldn't switch to \(name). \(why)" }

/// What a switch says when the server did not take the saved password.
public func serverSwitchPasswordRefusedWords(_ name: String) -> String {
    "\(name) didn't take the saved password. It may have been changed."
}

/// What a switch asked for while another is still running says.
public let serverSwitchBusy = "Still switching. Try again in a moment."
