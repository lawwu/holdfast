import Foundation
import Security

/// A Hugging Face-compatible API root, including any Artifactory repository path.
/// Credentials belong to that exact endpoint, not to every model host.
struct ModelDownloadSource {
    static let defaultEndpoint = "https://huggingface.co"
    static let preferenceKey = "modelDownloadEndpoint"
    let endpoint: String
    /// nil preserves Hugging Face's normal token discovery; an empty string
    /// selects an anonymous custom mirror.
    let token: String?

    struct Failure: LocalizedError, CustomStringConvertible {
        let description: String
        var errorDescription: String? { description }
        init(_ description: String) { self.description = description }
    }

    static var savedEndpoint: String {
        UserDefaults.standard.string(forKey: preferenceKey) ?? defaultEndpoint
    }

    static func normalize(_ value: String) throws -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return defaultEndpoint }
        guard !value.contains(where: { $0.isWhitespace }),
              var url = URLComponents(string: value),
              let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw Failure("Enter an HTTP or HTTPS API endpoint without credentials, a query, or a fragment. Put the access token in the token field.")
        }
        url.scheme = scheme
        url.host = host.lowercased()
        while url.path.hasSuffix("/") { url.path.removeLast() }
        guard let endpoint = url.url?.absoluteString else {
            throw Failure("The model download endpoint is not a valid URL.")
        }
        return endpoint
    }

    static func resolve(savedEndpoint: String, environment: [String: String],
                        savedToken: (String) throws -> String?) throws -> Self {
        let endpoint = try normalize(nonempty(environment["HF_ENDPOINT"]) ?? savedEndpoint)
        let token = try nonempty(environment["HF_TOKEN"]) ?? nonempty(savedToken(endpoint))
        return Self(endpoint: endpoint, token: token ?? (endpoint == defaultEndpoint ? nil : ""))
    }

    static func current() throws -> Self {
        try resolve(savedEndpoint: savedEndpoint, environment: ProcessInfo.processInfo.environment,
                    savedToken: ModelDownloadCredential.read)
    }

    static func save(endpoint: String, token: String) throws {
        let endpoint = try normalize(endpoint)
        try ModelDownloadCredential.write(nonempty(token), endpoint: endpoint)
        UserDefaults.standard.set(endpoint, forKey: preferenceKey)
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

/// Tokens stay out of UserDefaults and the settings copied into vault backups.
enum ModelDownloadCredential {
    private static func query(_ endpoint: String, service: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: endpoint]
    }

    static func read(endpoint: String) throws -> String? {
        try LegacyCompatibility.readCredential(suffix: "model-downloads",
            read: { try readStored(endpoint: endpoint, service: $0) },
            write: { try writeStored($0, endpoint: endpoint, service: $1) })
    }

    private static func readStored(endpoint: String, service: String) throws -> String? {
        var request = query(endpoint, service: service)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = item as? Data, let token = String(data: data, encoding: .utf8) else {
            throw ModelDownloadSource.Failure("The saved model access token could not be read. Save it again in Settings → Downloads.")
        }
        return token
    }

    static func write(_ token: String?, endpoint: String) throws {
        try LegacyCompatibility.writeCredential(token, suffix: "model-downloads",
            write: { try writeStored($0, endpoint: endpoint, service: $1) })
    }

    private static func writeStored(_ token: String?, endpoint: String, service: String) throws {
        let request = query(endpoint, service: service)
        guard let token else {
            let status = SecItemDelete(request as CFDictionary)
            if status != errSecItemNotFound { try check(status) }
            return
        }
        let attributes = [kSecValueData as String: Data(token.utf8)]
        let status = SecItemUpdate(request as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = request.merging(attributes) { _, new in new }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            try check(SecItemAdd(item as CFDictionary, nil))
        } else {
            try check(status)
        }
    }

    private static func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            throw ModelDownloadSource.Failure("Could not access the model token in Keychain (error \(status)).")
        }
    }
}

enum ModelFiles {
    /// Shared lookup for answer, embedding and reranker models. Incomplete app
    /// downloads must never be offered as ready to load.
    static func directory(repo: String, modelsDirectory: URL,
                          home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        let fm = FileManager.default
        let snapshots = home.appendingPathComponent(
            ".cache/huggingface/hub/models--\(repo.replacingOccurrences(of: "/", with: "--"))/snapshots")
        if let names = try? fm.contentsOfDirectory(atPath: snapshots.path) {
            for name in names.sorted().reversed() {
                let dir = snapshots.appendingPathComponent(name)
                if fm.fileExists(atPath: dir.appendingPathComponent("config.json").path) { return dir }
            }
        }
        let own = modelsDirectory.appendingPathComponent("models/\(repo)")
        return fm.fileExists(atPath: own.appendingPathComponent(".complete").path)
            && fm.fileExists(atPath: own.appendingPathComponent("config.json").path) ? own : nil
    }
}
