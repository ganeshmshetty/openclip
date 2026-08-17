// OnboardingView.swift
// OpenClip
//
// Renders the multi-step first-launch onboarding flow: Welcome (accessibility),
// AI assistant configuration, then recommended extensions.
// Drawn as a solid rounded card (border + shadow) on a transparent borderless
// window — a wizard is content, not navigation, so no Liquid Glass surface.
import SwiftUI
import AppKit
import Core

public enum OnboardingStep: Int, CaseIterable, Identifiable, Sendable {
    case welcome = 0
    case ai = 1
    case extensions = 2

    public var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .ai: return "AI Assistant"
        case .extensions: return "Extensions"
        }
    }
}

@MainActor
public struct OnboardingView: View {
    @ObservedObject private var permissionManager = PermissionManager.shared
    public var onComplete: @MainActor () -> Void

    @State private var step: OnboardingStep = .welcome

    public init(onComplete: @escaping @MainActor () -> Void) {
        self.onComplete = onComplete
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── App icon + name + step indicator ─────────────────────────────
            HStack(alignment: .top, spacing: 14) {
                Image(nsImage: AppIcon.image)
                    .resizable()
                    .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text("OpenClip")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Text selection tool for macOS")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    HStack(spacing: 12) {
                        HStack(spacing: 6) {
                            ForEach(OnboardingStep.allCases) { s in
                                Circle()
                                    .fill(step == s ? Color.accentColor : Color.primary.opacity(0.15))
                                    .frame(width: 8, height: 8)
                            }
                        }
                        Button {
                            DefaultSettingsStore.shared.set(.hasCompletedOnboarding, value: true)
                            onComplete()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary.opacity(0.6))
                                .font(.system(size: 14))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close")
                    }
                    Text("Step \(step.rawValue + 1) of \(OnboardingStep.allCases.count)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.bottom, 18)

            // ── Step heading ─────────────────────────────────────────────────
            HStack(alignment: .firstTextBaseline) {
                Text(step.title)
                    .font(.system(size: 20, weight: .bold))
                Spacer()
            }
            .padding(.bottom, 12)

            // ── Step content ─────────────────────────────────────────────────
            Group {
                switch step {
                case .welcome: welcomeContent
                case .ai: aiContent
                case .extensions: extensionsContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            // ── Footer ───────────────────────────────────────────────────────
            Divider()
                .padding(.top, 14)
                .padding(.bottom, 14)

            HStack {
                if step != .welcome {
                    Button("← Back") {
                        step = OnboardingStep(rawValue: step.rawValue - 1) ?? .welcome
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                Button {
                    if step == .extensions {
                        DefaultSettingsStore.shared.set(.hasCompletedOnboarding, value: true)
                        onComplete()
                    } else {
                        step = OnboardingStep(rawValue: step.rawValue + 1) ?? .extensions
                    }
                } label: {
                    Text(step == .extensions ? "Get Started" : "Continue →")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
        .frame(width: 520, height: 600)
        // Solid rounded card with a subtle border so its edge reads clearly against the
        // desktop. The border adapts to light/dark via Color.primary, and the shadow
        // renders into the window's transparent inset (see OnboardingWindowController).
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.2), radius: 18, x: 0, y: 6)
        .onAppear { permissionManager.startMonitoring() }
        .onDisappear { permissionManager.stopMonitoring() }
    }

    // MARK: - Welcome

    private var welcomeContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("How it works")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.bottom, 8)

            VStack(spacing: 1) {
                StepRow(number: "1", text: "Select any text in any app")
                StepRow(number: "2", text: "A small bar appears near your cursor")
                StepRow(number: "3", text: "Click an action — copy, search, run a script, and more")
            }
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            Spacer(minLength: 16)

            Divider()
                .padding(.bottom, 20)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accessibility Access")
                            .font(.system(size: 13, weight: .medium))
                        Text("Required to detect which text you've selected. You can grant this later from Preferences.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if permissionManager.isAccessibilityGranted {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.green)
                    } else {
                        Label("Not granted", systemImage: "xmark.circle.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }

                if !permissionManager.isAccessibilityGranted {
                    HStack(spacing: 8) {
                        Button("Open System Settings") {
                            permissionManager.requestAccessibilityPermission()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                    }
                }
            }
        }
    }

    // MARK: - AI

    private var aiContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Pick an engine and set it up. You can change this anytime in Preferences → AI.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                AIConfigureForm()
            }
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Extensions

    private var extensionsContent: some View {
        RecommendedExtensionsView()
    }
}

// MARK: - Step row

private struct StepRow: View {
    let number: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Text(number)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.primary.opacity(0.07)))

            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.primary)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.04))
    }
}
