import Foundation

/// The complete response contract for a cross-link decision, after thought-channel removal.
struct CrossLinkReply: Decodable {
    let link: Bool
    let reason: String

    static func parse(_ text: String) throws -> Self {
        // Foundation accepts trailing commas and duplicate keys. Require exactly
        // two string-keyed, primitive members before decoding the required fields.
        // JSON-escaped keys are allowed; duplicates or unknown keys cannot supply
        // both `link` and `reason`. The decoder validates escapes and field types.
        let string = #""(?:[^"\\\x00-\x1f]|\\(?:["\\/bfnrt]|u[0-9a-fA-F]{4}))*""#
        let space = #"[ \t\r\n]*"#
        let member = "\(string)\(space):\(space)(?:true|false|\(string))"
        let object = "\\A\(space)\\{\(space)\(member)\(space),\(space)\(member)\(space)\\}\(space)\\z"
        let syntax = try NSRegularExpression(pattern: object)
        guard syntax.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil else {
            throw DecodingError.dataCorrupted(.init(codingPath: [],
                debugDescription: "Cross-link reply must be one complete JSON object with Boolean link and string reason."))
        }
        return try JSONDecoder().decode(Self.self, from: Data(text.utf8))
    }
}
