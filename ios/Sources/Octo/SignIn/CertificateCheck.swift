import Foundation
import Security

/// Looks at client certificates for the sign-in form without putting them to use: the server in
/// use keeps its own certificate until a new one is saved with a server.
enum CertificateCheck {
    /// Opens a PKCS #12 file with its password and finds its identity, or throws when it cannot.
    static func validate(_ data: Data, password: String) throws {
        var items: CFArray?
        let status = SecPKCS12Import(data as CFData, [kSecImportExportPassphrase as String: password] as CFDictionary, &items)
        guard status == errSecSuccess, let first = (items as? [[String: Any]])?.first,
              first[kSecImportItemIdentity as String] != nil
        else { throw ClientCertificateError.unreadable }
    }

    /// Whether a kept server's certificate can still be read from the keychain. It is kept on
    /// this device only, so a phone restored from a backup has the server but not its certificate.
    static func isSaved(forServer id: String) -> Bool {
        Keychain.readData(for: "server.\(id).certificate") != nil
    }
}
