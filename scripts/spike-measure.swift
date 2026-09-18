#!/usr/bin/env xcrun swift
// T0.6 spike measurement: token counts and per-action latency against the on-device model.
// Run: xcrun swift scripts/spike-measure.swift
// Deliberately standalone (no app target) so it can run headless; the app's real prompts
// land in Sources/Polish/Model/Prompts.swift in T1.2.
import Foundation
import FoundationModels

let samples: [(name: String, text: String)] = [
    ("slack-short", "hey can u take a look at the PR when ur free, i think the retry logic is wrong but not sure"),
    ("slack-medium", "So the deploy failed again last night. Looks like the migration didnt run because the job timed out after 10 minutes, and then the api pods came up against the old schema and started 500ing on /orders. I rolled back at 2am. We should probably raise the timeout and add a health gate before the pods take traffic."),
    ("mail-formal", "Dear Anita, Thanks alot for sending over the revised statement of work. I have gone through it and it mostly looks fine, however I had a couple of question about the payment milestones and wether the QA phase is included in the fixed price. Could we maybe have a call sometime this week to discuss. Best regards, Saswat"),
    ("notes-long", String(repeating: "The onboarding flow has three steps today and each one loses people. Step one asks for a work email before showing any value. Step two requires a workspace name that cannot be changed later. Step three asks for teammates to invite, which nobody has at that point. We should show the product first and ask for identity only when something needs saving. ", count: 6)),
    ("one-word", "recieve")
]

let actions: [(name: String, instructions: String)] = [
    ("fixGrammar", "Correct the spelling and grammar. Return only the corrected text, no preamble."),
    ("improve", "Rewrite the text to be clearer and easier to read. Keep the meaning and the author's voice. Return only the rewritten text, no preamble."),
    ("summarize", "Summarize the text in at most three bullet points. Return only the bullets, no preamble."),
    ("shorten", "Rewrite the text to be shorter while keeping every fact. Return only the rewritten text, no preamble."),
    ("changeTone-professional", "Rewrite the text in a professional tone. Keep the meaning. Return only the rewritten text, no preamble."),
    ("expand", "Expand the text with more detail, inventing no facts. Return only the rewritten text, no preamble.")
]

let model = SystemLanguageModel.default
print("availability: \(model.availability)")
print("contextSize: \(model.contextSize)")
print("")

print("| sample | chars | tokens |")
print("|---|---:|---:|")
for s in samples {
    let t = try await model.tokenCount(for: s.text)
    print("| \(s.name) | \(s.text.count) | \(t) |")
}
print("")
print("| action | instruction tokens |")
print("|---|---:|")
for a in actions {
    print("| \(a.name) | \(try await model.tokenCount(for: a.instructions)) |")
}
print("")

print("| sample | action | in tok | out tok | seconds |")
print("|---|---|---:|---:|---:|")
for s in samples {
    for a in actions {
        let session = LanguageModelSession(instructions: a.instructions)
        session.prewarm()
        let start = ContinuousClock.now
        do {
            let out = try await session.respond(to: s.text).content
            let secs = Double(start.duration(to: .now).components.attoseconds) / 1e18
                + Double(start.duration(to: .now).components.seconds)
            print("| \(s.name) | \(a.name) | \(try await model.tokenCount(for: s.text)) | \(try await model.tokenCount(for: out)) | \(String(format: "%.2f", secs)) |")
        } catch {
            print("| \(s.name) | \(a.name) | - | - | FAILED: \(error) |")
        }
    }
}
