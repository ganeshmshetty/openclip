// PasteAvailability.swift
// OpenClip
//
// The single effective paste-availability decision. The per-app `denyPaste` rule is an explicit
// user preference and wins over the live AX probe; when no rule applies, the probe result is used
// as-is. `nil` means "unknown" and keeps its two risk postures downstream: gating keeps Paste/Cut
// visible, delivery falls back to copy. Pure Core — no AppKit.
public enum PasteAvailability {
    /// Combines the per-app rules with the live probe result into one answer. `denyPaste` wins
    /// (safest — never paste into an app the user forbade) even over a conflicting probe result.
    public static func effective(policy: AppPolicyContext, probe: Bool?) -> Bool? {
        if policy.denyPaste { return false }
        return probe
    }

    /// Whether the live AX probe must run for this policy. A `denyPaste` rule already answers
    /// definitively, so no probe work — and no Accessibility dependency — is needed for those apps.
    public static func needsProbe(policy: AppPolicyContext) -> Bool {
        !policy.denyPaste
    }
}