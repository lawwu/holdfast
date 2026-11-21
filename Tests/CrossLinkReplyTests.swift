import Foundation

@main struct CrossLinkReplyTests {
    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: message, code: 1) }
    }

    static func main() throws {
        let valid: [(String, Bool, String)] = [
            (#"{"link":true,"reason":"same pump"}"#, true, "same pump"),
            (#"{"link":false,"reason":"different item"}"#, false, "different item"),
            (" \n{ \"reason\" : \"same pump\",\t\"link\": true }\r\n", true, "same pump"),
            (#"{"link":true,"reason":""}"#, true, ""),
            (#"{"link":true,"reason":"Quote: \"pump\"; path: a\\b\/c\nnext"}"#, true, "Quote: \"pump\"; path: a\\b/c\nnext"),
            (#"{"link":true,"reason":"Café 🏡 \uD83C\uDFE1"}"#, true, "Café 🏡 🏡"),
            (#"{"\u006cink":true,"rea\u0073on":"same pump"}"#, true, "same pump"),
            (#"{"reason":"Braces { }, comma, and \"link\":false are text.","link":true}"#, true, "Braces { }, comma, and \"link\":false are text.")]
        for (text, link, reason) in valid {
            let reply: CrossLinkReply
            do { reply = try CrossLinkReply.parse(text) }
            catch { throw NSError(domain: "Valid reply rejected: \(text) — \(error)", code: 1) }
            try require(reply.link == link && reply.reason == reason, "Valid reply changed: \(text)")
        }
        let invalid = [
            "", "I cannot assist with this request.", #"{"link":true,"#,
            #"{"link":"true","reason":"same pump"}"#,
            #"{"link":"false","reason":"same pump"}"#,
            #"{"link":1,"reason":"same pump"}"#,
            #"{"link":0,"reason":"same pump"}"#,
            #"{"link":null,"reason":"same pump"}"#,
            #"{"link":true}"#, #"{"reason":"same pump"}"#,
            #"{"link":true,"reason":null}"#, #"{"link":true,"reason":12}"#,
            #"{"link":true,"reason":{"text":"same pump"}}"#,
            #"{"link":true,"reason":["same pump"]}"#,
            #"[{"link":true,"reason":"same pump"}]"#,
            #"{"result":{"link":true,"reason":"same pump"}}"#,
            #"{"link":true,"reason":"same pump"}{"link":false,"reason":"no"}"#,
            #"I refuse, but here is an example: {"link":true,"reason":"same pump"}"#,
            #"{"link":true,"reason":"same pump"} trailing text"#,
            "```json\n{\"link\":true,\"reason\":\"same pump\"}\n```",
            #"{"link":true,"reason":"same pump",}"#,
            #"{"link":true,,"reason":"same pump"}"#,
            #"{"link":true,/* comment */"reason":"same pump"}"#,
            #"{"link":true,"link":false,"reason":"same pump"}"#,
            #"{"link":true,"link":true}"#,
            #"{"link":true,"li\u006ek":false,"reason":"same pump"}"#,
            #"{"link":True,"reason":"same pump"}"#,
            #"{link:true,"reason":"same pump"}"#,
            #"{"link":true,"reason":"bad\qescape"}"#,
            "{\"link\":true,\"reason\":\"raw\nnewline\"}",
            #"{"link":true,"reason":"\uD800"}"#,
            #"{"link":true,"reason":"same pump","extra":true}"#,
            #"{"link":true,"explanation":"same pump"}"#, "{}", "true"]
        for text in invalid {
            var rejected = false
            do { _ = try CrossLinkReply.parse(text) } catch { rejected = true }
            try require(rejected, "Malformed reply accepted: \(text)")
        }
        // Replay the frozen real model responses without loading a model or changing labels.
        var replayed = 0
        if let path = CommandLine.arguments.dropFirst().first {
            let root = URL(fileURLWithPath: path)
            for folder in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                where folder.lastPathComponent.hasPrefix("round-") && folder.hasDirectoryPath {
                let lines = try String(contentsOf: folder.appendingPathComponent("stdout.jsonl"), encoding: .utf8)
                for line in lines.split(separator: "\n") {
                    let row = try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
                    guard row["kind"] as? String == "trial" else { continue }
                    let reply = try CrossLinkReply.parse(row["raw"] as! String)
                    try require(reply.link == row["link"] as? Bool, "Recorded verdict changed: \(row["id"]!)")
                    replayed += 1
                }
            }
            try require(replayed == 102, "Expected 102 recorded replies, got \(replayed)")
        }
        print("PASS \(valid.count + invalid.count) parser cases; \(replayed) recorded model replies preserve their decisions")
    }
}
