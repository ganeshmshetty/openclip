// AIAdditionalInstruction.swift
// OpenClip
//
// The `{{additional_instruction}}` prompt variable of AI presets that ask for a one-time
// instruction before they run (`AIActionPreset.requestsAdditionalInstruction`). Pure string rules
// shared by the Preferences editors (insert on enable, remove on disable) and the popup's run path
// (substitute the typed instruction), so no view re-implements the replacement. The selected text
// is never part of this: it still travels to the provider separately, in its own `<text>` block.
import Foundation

public enum AIAdditionalInstruction {
    /// The variable a preset prompt carries where the run-time instruction belongs.
    public static let placeholder = "{{additional_instruction}}"

    /// Heading used when a preset asks for an instruction but its prompt has no placeholder
    /// (typed away, or saved by hand): the instruction is appended under it instead of dropped.
    static let appendedHeading = "Additional instruction:"

    public static func containsPlaceholder(_ prompt: String) -> Bool {
        prompt.contains(placeholder)
    }

    /// The prompt for one run: every placeholder replaced by `instruction` (trimmed at its ends,
    /// otherwise verbatim — multiple lines, Unicode and `$`/`\` are inserted literally). Without a
    /// placeholder the instruction is appended under `appendedHeading`, so a run never silently
    /// loses what the user typed. An empty instruction removes the placeholder instead, so an
    /// unresolved variable can never reach the provider.
    public static func resolve(prompt: String, with instruction: String) -> String {
        let instruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { return removingPlaceholder(from: prompt) }
        if containsPlaceholder(prompt) {
            return prompt.replacingOccurrences(of: placeholder, with: instruction)
        }
        let base = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return instruction }
        return "\(base)\n\n\(appendedHeading)\n\(instruction)"
    }

    /// Turning the option on: appends the placeholder on its own paragraph unless the prompt
    /// already has one somewhere (the user may have positioned it already).
    public static func insertingPlaceholder(into prompt: String) -> String {
        guard !containsPlaceholder(prompt) else { return prompt }
        let base = trimmingTrailingWhitespace(prompt)
        return base.isEmpty ? placeholder : "\(base)\n\n\(placeholder)"
    }

    /// Turning the option off: removes every placeholder and tidies only the whitespace the
    /// removal left behind — a line that held just the placeholder goes away with one of the blank
    /// lines around it, and an inline placeholder takes one adjacent space with it. The rest of the
    /// prompt is left exactly as written, so on → off round-trips to the original prompt.
    public static func removingPlaceholder(from prompt: String) -> String {
        guard containsPlaceholder(prompt) else { return prompt }
        let lines = prompt.components(separatedBy: "\n")
        var kept: [String] = []
        var dropNextBlank = false
        for line in lines {
            guard line.contains(placeholder) else {
                let isBlank = line.trimmingCharacters(in: .whitespaces).isEmpty
                if dropNextBlank && isBlank {
                    dropNextBlank = false
                    continue
                }
                dropNextBlank = false
                kept.append(line)
                continue
            }
            let stripped = line
                .replacingOccurrences(of: " \(placeholder)", with: "")
                .replacingOccurrences(of: "\(placeholder) ", with: "")
                .replacingOccurrences(of: placeholder, with: "")
            if stripped.trimmingCharacters(in: .whitespaces).isEmpty {
                // A whole-line placeholder between two paragraphs: drop one surrounding blank line
                // too, so the paragraphs keep a single blank line between them.
                let previousIsBlank = kept.last.map { $0.trimmingCharacters(in: .whitespaces).isEmpty } ?? true
                dropNextBlank = previousIsBlank
            } else {
                kept.append(stripped)
            }
        }
        return trimmingTrailingWhitespace(kept.joined(separator: "\n"))
    }

    private static func trimmingTrailingWhitespace(_ text: String) -> String {
        var result = text
        while let last = result.last, last.isWhitespace || last.isNewline {
            result.removeLast()
        }
        return result
    }
}
