import Foundation
import Security

/// Keeps the ChatGPT sign-in. Never written anywhere else.
///
/// iPad: the keychain, on this device only.
/// Mac: a file only this user can read, in Application Support. The Mac app is ad-hoc signed and replaces itself on
/// every release; the login keychain trusts one exact build, so a keychain item would ask for the password after
/// every update.
enum SecretStore {
    static func data(_ name: String) -> Data? {
        #if os(macOS)
        try? Data(contentsOf: fileURL(name))
        #else
        var query = query(name)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
        #endif
    }

    /// Replaces the secret, or deletes it when `data` is nil.
    static func set(_ data: Data?, for name: String) {
        #if os(macOS)
        let url = fileURL(name)
        guard let data else { try? FileManager.default.removeItem(at: url); return }
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // Created empty with owner-only permissions first, so the secret is never readable by others, even briefly.
        FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        try? data.write(to: url)
        #else
        SecItemDelete(query(name) as CFDictionary)
        guard let data else { return }
        var attributes = query(name)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
        #endif
    }

    #if os(macOS)
    private static func fileURL(_ name: String) -> URL {
        URL.applicationSupportDirectory.appending(path: "Situations/\(name).json")
    }
    #else
    private static func query(_ name: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.martyvasquez.SituationSim",
            kSecAttrAccount as String: name,
        ]
    }
    #endif
}
