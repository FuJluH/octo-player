import Foundation

/// Which account a server's things are kept for: the first 8 bytes of SHA-256 of
/// "username@address", in hex. The address is written the way the other apps write it, with a
/// slash after a bare host.
public func serverAccountKey(_ username: String, _ address: String) -> String {
    Hashes.hex(Hashes.sha256(Array("\(username)@\(address)".utf8)).prefix(8))
}
