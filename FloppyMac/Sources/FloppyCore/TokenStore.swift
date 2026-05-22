import Foundation
import Security

public protocol FloppyTokenStore: Sendable {
    func save(token: String, accountID: String) throws
    func load(accountID: String) throws -> String?
    func delete(accountID: String) throws
}

public enum FloppyTokenStoreError: Error, LocalizedError {
    case keychain(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .keychain(let status):
            "Keychain operation failed with status \(status)."
        }
    }
}

public struct KeychainTokenStore: FloppyTokenStore {
    private let service: String
    private let accessGroup: String?

    public init(service: String = "com.floppy.mac.token", accessGroup: String? = KeychainTokenStore.defaultAccessGroup()) {
        self.service = service
        self.accessGroup = accessGroup
    }

    public static func `default`(service: String = "com.floppy.mac.token") -> KeychainTokenStore {
        KeychainTokenStore(service: service, accessGroup: defaultAccessGroup())
    }

    public static func defaultAccessGroup(bundle: Bundle = .main) -> String? {
        guard
            let value = bundle.object(forInfoDictionaryKey: "FloppyKeychainAccessGroup") as? String,
            !value.isEmpty,
            !value.contains("$(")
        else {
            return nil
        }

        return value
    }

    public func save(token: String, accountID: String) throws {
        try delete(accountID: accountID)

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(token.utf8)
        ]
        addAccessGroup(to: &query)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw FloppyTokenStoreError.keychain(status)
        }
    }

    public func load(accountID: String) throws -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        addAccessGroup(to: &query)

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw FloppyTokenStoreError.keychain(status)
        }
        return String(data: data, encoding: .utf8)
    }

    public func delete(accountID: String) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID
        ]
        addAccessGroup(to: &query)

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw FloppyTokenStoreError.keychain(status)
        }
    }

    private func addAccessGroup(to query: inout [String: Any]) {
        guard let accessGroup else {
            return
        }

        query[kSecAttrAccessGroup as String] = accessGroup
    }
}

public final class InMemoryTokenStore: FloppyTokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [String: String] = [:]

    public init() {}

    public func save(token: String, accountID: String) throws {
        lock.lock()
        defer { lock.unlock() }
        tokens[accountID] = token
    }

    public func load(accountID: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return tokens[accountID]
    }

    public func delete(accountID: String) throws {
        lock.lock()
        defer { lock.unlock() }
        tokens.removeValue(forKey: accountID)
    }
}
