import Testing
@testable import Polish

@Test("every instruction fits the 120-token prompt budget", arguments: Prompts.all)
func instructionFitsTokenBudget(instruction: String) async throws {
    guard ModelService.shared.availability == .ready else {
        // ponytail: no Apple Intelligence on this machine, so no real tokenizer. 4 characters per
        // token is a safe upper bound for English, and the exact count runs wherever the model does.
        #expect(instruction.count <= 120 * 4)
        return
    }
    let tokens = try await ModelService.shared.tokenCount(for: instruction)
    #expect(tokens <= 120)
}

@Test("every action resolves to a non-empty output-only instruction", arguments: Action.grid + Tone.allCases.map(Action.changeTone))
func everyActionHasInstructions(action: Action) {
    let instruction = action.instructions
    #expect(!instruction.isEmpty)
    #expect(instruction.contains("no preamble"))
}

@Test("each tone produces its own instruction")
func tonesDiffer() {
    let instructions = Set(Tone.allCases.map(Prompts.changeTone))
    #expect(instructions.count == Tone.allCases.count)
}
