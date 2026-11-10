import Foundation

// MARK: - Router
//
// One box for everything. Instead of the person choosing Ask, Research or a
// job, each request is routed:
// - a task over the whole vault ("link my notes") starts that job;
// - a question that needs totals, comparisons, lists or several notes goes to
//   Research (search, read notes, query the CSV tables, in steps);
// - anything else gets a direct answer, and escalates to Research when that
//   answer comes back empty-handed (no sources, or "the notes don't say").
// Rules, not a model: they cost nothing, they are predictable, and the
// escalation catches what they miss. eval/household/route.py scores them
// against which mode actually answered each question better.

enum Route: String {
    case answer, research, crossLink, bulkImport, edit
}

enum Router {
    /// Requests, not questions: "link my notes", "please cross-link the vault", "suggest links".
    static let crossLink = #"(?i)^\s*(please\s+)?(cross[- ]?link|link (up )?(all |my |the |these |related )?notes|connect (all |my |the )?notes|suggest (some |more )?links|add (see also )?links)\b"#
    static let bulkImport = #"(?i)^\s*(please\s+)?((bulk )?import (my|a|an|the|these|some|all|files|folder|everything)\b|bring in (a |my |the )?(folder|files|archive|export))"#
    /// Cues that a question needs numbers from tables, a list across notes, or a comparison over time.
    static let research = #"(?i)\b(how (much|many|often)|total|sum\b|average|per (day|week|month|year)|each (week|month|year)|by month|trend|compare|comparison|versus|vs\.?|across|over the (last|past)|since|year[- ]to[- ]date|ytd|all (the|of)|list (all|every|the)|every time|which (months?|weeks?|years?)|most|least|highest|lowest|biggest|largest|spent|spend|spending|miles|workouts?|runs?\b|history of|timeline|changed|change over)\b"#

    /// Requests to change a note: "mark … done", "tick off …", "add … to my list", "update …".
    static let edit = #"(?i)^\s*(please\s+|can you\s+|could you\s+)?(mark|tick( off)?|check off|uncheck|cross off|update|change|set(?! up)|add|append|record|log|note that|fix|correct|rename|remove|delete|replace)\b"#

    static func route(_ q: String) -> Route {
        func has(_ p: String) -> Bool { q.range(of: p, options: .regularExpression) != nil }
        let question = q.trimmingCharacters(in: .whitespaces).hasSuffix("?")
        if has(crossLink), !question { return .crossLink }
        if has(bulkImport), !question { return .bulkImport }
        if has(edit) { return .edit }
        if has(research) { return .research }
        return .answer
    }

    /// A direct answer that found nothing: worth a second, deeper try.
    static func shouldEscalate(_ a: Answer) -> Bool {
        a.sources.isEmpty || a.text.range(of: #"(?i)(notes|passages|vault|context) (do(es)? not|don't|doesn't) (say|cover|contain|mention|include)|no (information|record|mention) (of|about|on)|not (mentioned|covered|recorded) in"#,
                                          options: .regularExpression) != nil
    }

    static func label(_ r: Route, escalated: Bool) -> String {
        switch r {
        case .research: return escalated ? "Looked deeper: searched notes, read them and checked tables" : "Researched: searched notes, read them and checked tables"
        case .answer: return "Answered from the closest passages"
        case .crossLink: return "Started the cross-link job"
        case .bulkImport: return "Opened Bulk Import"
        case .edit: return "Read the note and proposed a change for the Inbox"
        }
    }
}
