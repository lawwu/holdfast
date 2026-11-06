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
    case answer, research, crossLink, bulkImport
}

enum Router {
    static let crossLink = #"(?i)\b(cross[- ]?link|link (up )?(my |the |these |related )?notes|connect (my |the )?notes|suggest (some )?links|add (see also|links))\b"#
    static let bulkImport = #"(?i)^\s*(bulk )?import\b|\bbring in (a |my )?(folder|files|archive|export)"#
    /// Cues that a question needs numbers from tables, a list across notes, or a comparison over time.
    static let research = #"(?i)\b(how (much|many|often)|total|sum|average|per (day|week|month|year)|each (week|month|year)|by month|trend|compare|comparison|versus|vs\.?|across|over the (last|past)|since|year[- ]to[- ]date|ytd|all (the|of)|list (all|every|the)|every time|which (months?|weeks?|years?)|most|least|highest|lowest|biggest|largest|spent|spend|spending|miles|workouts?|runs?\b|history of|timeline|changed|change over)"#

    static func route(_ q: String) -> Route {
        func has(_ p: String) -> Bool { q.range(of: p, options: .regularExpression) != nil }
        if has(crossLink) { return .crossLink }
        if has(bulkImport) { return .bulkImport }
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
        }
    }
}
