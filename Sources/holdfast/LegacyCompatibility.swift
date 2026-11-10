import Foundation

/// Historical values are deliberately confined here. Keep these exact spellings:
/// existing installations and protected folders must remain recognizable.
enum LegacyCompatibility {
    static let dataFolder = "MacKB"
    static let cliDomain = "mackb"
    static let bundleID = "net.lawrencewu.mackb"
    static let previousBundleID = "net.lawrencewu.holdfast"
    static let stateFolder = ".mackb"
    static let environmentPrefix = "MACKB_"
    static let privateProfileID = "counseling"
    static let includePrivateFlag = "--include-counseling"

    static func isProtectedFolder(_ name: String) -> Bool {
        name.hasPrefix("ministry") || name.contains("counsel")
    }

    static func preferenceDomains(app: Bool, bundle: String?) -> [String] {
        guard app else { return [cliDomain] }
        let suffix = bundle?.hasPrefix("app.holdfast") == true
            ? String(bundle!.dropFirst("app.holdfast".count)) : ""
        return [previousBundleID + suffix, bundleID]
    }

    static func profileID(_ id: String?) -> String? {
        id == privateProfileID ? "private" : id
    }

    static func readCredential(suffix: String, read: (String) throws -> String?,
                               write: (String?, String) throws -> Void) throws -> String? {
        let current = "app.holdfast." + suffix
        if let value = try read(current) { return value }
        guard let value = try read(previousBundleID + "." + suffix) else { return nil }
        // Copy before returning. The previous app can still read its own entry.
        try write(value, current)
        return value
    }

    static func writeCredential(_ value: String?, suffix: String,
                                write: (String?, String) throws -> Void) throws {
        try write(value, "app.holdfast." + suffix)
        // An explicitly cleared or replaced credential must not return on a later read.
        try write(nil, previousBundleID + "." + suffix)
    }
}
