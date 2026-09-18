import Testing
@testable import Polish

/// T2.4 — the estimate the popover shows before anything runs, against `PRD.md`
/// "Strategy by text length".
struct SizeEstimateTests {
    @Test func shortSelectionIsOnePart() {
        let estimate = SizeEstimate.make(tokens: 400, paragraphs: 3, singlePassLimit: 1_659)
        #expect(estimate.parts == 1)
        #expect(!estimate.isLong)
        #expect(estimate.label == "~400 tokens")
        #expect(estimate.warning == nil)
    }

    @Test func overBudgetSelectionCountsParts() {
        let estimate = SizeEstimate.make(tokens: 4_200, paragraphs: 8, singlePassLimit: 1_659)
        #expect(estimate.parts == 8)
        #expect(estimate.label.contains("processing in 8 parts"))
    }

    /// One long paragraph is still more than one call, so the label never claims "1 part".
    @Test func overBudgetSingleParagraphIsAtLeastTwoParts() {
        #expect(SizeEstimate.make(tokens: 4_200, paragraphs: 1, singlePassLimit: 1_659).parts == 2)
    }

    @Test func everyActionIsOfferedBelowTheVeryLongThreshold() {
        let estimate = SizeEstimate.make(tokens: 11_999, paragraphs: 40, singlePassLimit: 1_659)
        #expect(!estimate.isVeryLong)
        #expect(Action.grid.allSatisfy(estimate.isEnabled))
        #expect(estimate.warning == nil)
    }

    @Test func veryLongSelectionOffersOnlyFixGrammarAndSummarize() {
        let estimate = SizeEstimate.make(tokens: 12_001, paragraphs: 60, singlePassLimit: 1_659)
        #expect(estimate.isVeryLong)
        #expect(estimate.isEnabled(.fixGrammar))
        #expect(estimate.isEnabled(.summarize))
        #expect(!estimate.isEnabled(.improve))
        #expect(!estimate.isEnabled(.shorten))
        #expect(!estimate.isEnabled(.expand))
        #expect(!estimate.isEnabled(.changeTone(.friendly)))
        #expect(estimate.warning != nil)
    }
}
