// OnboardingView.swift
// OpenClip
//
// Renders the multi-step first-launch onboarding flow: Welcome (accessibility),
// AI assistant configuration, recommended extensions, then a Finish summary.
// Presented in a Liquid Glass panel on macOS 26+ with a standard-material
// fallback on macOS 14-15.
import SwiftUI
import AppKit

public enum OnboardingStep: Int, CaseIterable, Identifiable, Sendable {
    case welcome = 0
    case ai = 1
    case extensions = 2
    case finish = 3

    public var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .ai: return "AI Assistant"
        case .extensions: return "Extensions"
        case .finish: return "Finish"
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
                            onComplete()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary.opacity(0.6))
                                .font(.system(size: 14))
                        }
                        .buttonStyle(.plain)
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
                case .finish: finishContent
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
                    if step == .finish {
                        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                        onComplete()
                    } else {
                        step = OnboardingStep(rawValue: step.rawValue + 1) ?? .finish
                    }
                } label: {
                    Text(step == .finish ? "Get Started" : "Continue →")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
        .frame(width: 520, height: 600)
        .glassSurface(.regular, cornerRadius: 20)
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

            Divider()
                .padding(.vertical, 20)

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

            Spacer(minLength: 8)

            Text("Runs 100% locally — no data leaves your Mac.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
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

    // MARK: - Finish

    private var finishContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Preview your popup bar and choose how it looks.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                PopupPreview()
                PopupThemeSelector()
            }
        }
        .scrollContentBackground(.hidden)
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
