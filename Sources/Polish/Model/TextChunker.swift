import Foundation
import NaturalLanguage

/// Splits long input into pieces that each fit the model's window.
///
/// Two modes, matching `PRD.md` "Chunking rules":
/// - ``paragraphs(_:)`` for rewrites — one paragraph in, one paragraph out, so stitching is trivial
///   and the author's blank-line structure survives.
/// - ``budgeted(_:maxTokens:overlapSentences:)`` for summaries — sentences packed up to a measured
///   token budget, with the tail of the previous chunk repeated for continuity.
///
/// Splits never fall mid-sentence, with one exception: a single sentence larger than the whole
/// budget is broken on word boundaries, because the alternative is a chunk the model would reject.
struct TextChunker: Sendable {
    let counter: any TokenCounting

    init(counter: any TokenCounting) {
        self.counter = counter
    }

    init(service: ModelService = .shared) {
        self.init(counter: service)
    }

    /// Paragraphs, in order, with surrounding whitespace trimmed and blank ones dropped.
    static func paragraphs(_ text: String) -> [String] {
        var paragraphs: [String] = []
        var current: [Substring] = []

        func flush() {
            let paragraph = current.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !paragraph.isEmpty { paragraphs.append(paragraph) }
            current = []
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                flush()
            } else {
                current.append(line)
            }
        }
        flush()
        return paragraphs
    }

    /// Sentences, in order, using `NLTokenizer` so abbreviations and quotes do not split a sentence.
    static func sentences(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty { sentences.append(sentence) }
            return true
        }
        return sentences
    }

    /// Packs sentences into chunks of at most `maxTokens`, repeating the last `overlapSentences`
    /// sentences of each chunk at the head of the next one so summaries keep their thread.
    ///
    /// Every chunk is measured, never estimated. Returns `[]` for text with no sentences.
    func budgeted(_ text: String, maxTokens: Int, overlapSentences: Int = 1) async throws -> [String] {
        guard maxTokens > 0 else { return [] }

        var pieces: [Piece] = []
        for sentence in Self.sentences(text) {
            let cost = try await counter.tokenCount(for: sentence)
            pieces += try await split(sentence, cost: cost, maxTokens: maxTokens)
        }

        var chunks: [String] = []
        var current: [Piece] = []
        var currentCost = 0

        for piece in pieces {
            if !current.isEmpty, currentCost + piece.cost > maxTokens {
                chunks.append(current.map(\.text).joined(separator: " "))
                // Carry the tail forward, dropping as much of it as the next sentence needs room for.
                current = Array(current.suffix(max(0, overlapSentences)))
                currentCost = current.reduce(0) { $0 + $1.cost }
                while !current.isEmpty, currentCost + piece.cost > maxTokens {
                    currentCost -= current.removeFirst().cost
                }
            }
            current.append(piece)
            currentCost += piece.cost
        }
        if !current.isEmpty {
            chunks.append(current.map(\.text).joined(separator: " "))
        }
        return chunks
    }

    private struct Piece {
        let text: String
        let cost: Int
    }

    /// Halves an over-budget sentence on word boundaries until each part fits, or until a single
    /// word is left — one word larger than the entire budget is returned as is, and the caller's
    /// `contextSizeExceeded` retry is the backstop.
    private func split(_ sentence: String, cost: Int, maxTokens: Int) async throws -> [Piece] {
        guard cost > maxTokens else { return [Piece(text: sentence, cost: cost)] }

        let words = sentence.split(whereSeparator: \.isWhitespace)
        guard words.count > 1 else { return [Piece(text: sentence, cost: cost)] }

        var parts: [Piece] = []
        for half in [words.prefix(words.count / 2), words.suffix(words.count - words.count / 2)] {
            let text = half.joined(separator: " ")
            let halfCost = try await counter.tokenCount(for: text)
            parts += try await split(text, cost: halfCost, maxTokens: maxTokens)
        }
        return parts
    }
}
