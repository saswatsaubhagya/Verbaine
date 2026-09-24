import Foundation

/// Where a multi-call action has got to, and the result so far. Shared by ``ParagraphRewriter``
/// and ``MapReduceSummarizer`` so the popover renders "Part 3 of 8" the same way for both.
struct PartProgress: Sendable, Equatable {
    let part: Int
    let total: Int
    let text: String
}
