import Foundation

/// Word-level diff between the original selection and the model's rewrite, for the two-pane
/// result view: the left pane shows the original with removals marked, the right pane shows the
/// result with insertions marked.
enum DiffEngine {
    enum Kind: Sendable {
        case same
        case inserted
        case removed
    }

    struct Segment: Equatable, Sendable {
        let text: String
        let kind: Kind
    }

    /// Splits into words that carry their trailing whitespace, so joining the tokens rebuilds the
    /// input exactly — newlines and double spaces in the original survive the round trip.
    static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inWhitespace = false

        for character in text {
            if character.isWhitespace {
                current.append(character)
                inWhitespace = true
            } else {
                if inWhitespace {
                    tokens.append(current)
                    current = ""
                    inWhitespace = false
                }
                current.append(character)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    /// Longest-common-subsequence diff over words. Tokens match on their trimmed form, so a word
    /// that only changed the whitespace after it does not read as an edit.
    ///
    /// An unchanged word carries the result's whitespace, not the original's, so the result pane
    /// reproduces the rewrite byte for byte and the original pane may differ from the selection in
    /// whitespace alone.
    ///
    /// ponytail: O(n × m) table. Selections are chat messages and paragraphs; if whole documents
    /// ever reach here, switch to Myers.
    static func diff(original: String, result: String) -> [Segment] {
        let old = tokenize(original)
        let new = tokenize(result)
        let keyOld = old.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let keyNew = new.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        // lengths[i][j] = LCS length of old[i...] and new[j...].
        var lengths = [[Int]](repeating: [Int](repeating: 0, count: new.count + 1), count: old.count + 1)
        for i in stride(from: old.count - 1, through: 0, by: -1) {
            for j in stride(from: new.count - 1, through: 0, by: -1) {
                lengths[i][j] = keyOld[i] == keyNew[j]
                    ? lengths[i + 1][j + 1] + 1
                    : max(lengths[i + 1][j], lengths[i][j + 1])
            }
        }

        var segments: [Segment] = []
        var i = 0, j = 0
        while i < old.count, j < new.count {
            if keyOld[i] == keyNew[j] {
                segments.append(Segment(text: new[j], kind: .same))
                i += 1
                j += 1
            } else if lengths[i + 1][j] >= lengths[i][j + 1] {
                segments.append(Segment(text: old[i], kind: .removed))
                i += 1
            } else {
                segments.append(Segment(text: new[j], kind: .inserted))
                j += 1
            }
        }
        while i < old.count {
            segments.append(Segment(text: old[i], kind: .removed))
            i += 1
        }
        while j < new.count {
            segments.append(Segment(text: new[j], kind: .inserted))
            j += 1
        }
        return segments
    }
}
