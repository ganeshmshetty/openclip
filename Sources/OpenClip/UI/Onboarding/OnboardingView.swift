// OnboardingView.swift
// OpenClip
//
// Native macOS onboarding flow following System Settings conventions: solid window background,
// hierarchical SF Symbols, flat system inset cards, no web drop-shadows.
import SwiftUI
import AppKit
import Core

public enum OnboardingStep: Int, CaseIterable, Identifiable, Sendable {
    case welcome = 0
    case permission = 1
    case extensions = 2
    case done = 3

    public var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .permission: return "Access"
        case .extensions: return "Extensions"
        case .done: return "Try It"
        }
    }
}

// MARK: - Tactile Button Styles

public struct MacPrimaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 6.5)
            .background(
                LinearGradient(
                    colors: [Color.accentColor, Color.accentColor.opacity(0.88)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
            )
            .shadow(
                color: Color.accentColor.opacity(configuration.isPressed ? 0.05 : 0.2),
                radius: configuration.isPressed ? 1.5 : 3,
                x: 0,
                y: configuration.isPressed ? 0.5 : 1.5
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

public struct MacSecondaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundColor(.primary.opacity(0.85))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .settingsGlassCapsule()
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Onboarding View

@MainActor
public struct OnboardingView: View {
    @ObservedObject private var permissionManager = PermissionManager.shared
    public var onComplete: @MainActor () -> Void

    @State private var step: OnboardingStep = .welcome
    @State private var slideEdge: Edge = .trailing
    @State private var hasDetectedSelection = false
    @State private var isSkipHovered = false
    @State private var didRequestScreenRecording = false

    public init(onComplete: @escaping @MainActor () -> Void) {
        self.onComplete = onComplete
    }

    public var body: some View {
        VStack(spacing: 0) {
            // ── Top Header: Step Indicator ─────────────────────────────
            topBar
                .padding(.horizontal, 28)
                .padding(.top, 20)
                .padding(.bottom, 12)

            // ── Center Content Area ────────────────────────────────────
            VStack {
                Group {
                    switch step {
                    case .welcome: welcomeStep
                    case .permission: permissionStep
                    case .extensions: extensionsStep
                    case .done: doneStep
                    }
                }
                .transition(.push(from: slideEdge))
                .padding(.top, 8)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 28)

            // ── Bottom Navigation Bar ──────────────────────────────────
            bottomBar
                .padding(.horizontal, 28)
                .padding(.bottom, 20)
                .padding(.top, 12)
        }
        .frame(width: 520, height: 470)
        .background {
            // Same translucent surface as the Settings window.
            ZStack {
                VisualEffectView(material: .sidebar, blendingMode: .behindWindow, state: .active)
                SettingsDesignTokens.windowScrim
            }
            .ignoresSafeArea()
        }
        .onAppear { permissionManager.startMonitoring() }
        .onDisappear { permissionManager.stopMonitoring() }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Spacer()

            // Compact Apple-style Progress Track
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 3)

                    Capsule()
                        .fill(Color.accentColor)
                        .frame(
                            width: max(8, geo.size.width * CGFloat(step.rawValue + 1) / CGFloat(OnboardingStep.allCases.count)),
                            height: 3
                        )
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: step)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(width: 72, height: 8)

            if step != .done && step != .permission {
                Button {
                    completeOnboarding()
                } label: {
                    Text("Skip")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(isSkipHovered ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                .onHover { isSkipHovered = $0 }
            }
        }
    }

    // MARK: - Bottom Navigation Bar

    private var bottomBar: some View {
        HStack {
            if step != .welcome {
                Button {
                    slideEdge = .leading
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        step = OnboardingStep(rawValue: step.rawValue - 1) ?? .welcome
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9.5, weight: .bold))
                        Text("Back")
                    }
                }
                .buttonStyle(MacSecondaryButtonStyle())
            }

            Spacer()

            Button {
                if step == .done {
                    completeOnboarding()
                } else {
                    slideEdge = .trailing
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        step = OnboardingStep(rawValue: step.rawValue + 1) ?? .done
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(continueTitle)
                    Image(systemName: step == .done ? "arrow.right.circle.fill" : "chevron.right")
                        .font(.system(size: 9.5, weight: .bold))
                }
            }
            .buttonStyle(MacPrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
        }
    }

    private var continueTitle: String {
        switch step {
        case .done: return String(localized: "Get Started")
        case .permission where !permissionManager.isAccessibilityGranted: return String(localized: "Continue without access")
        default: return String(localized: "Continue")
        }
    }

    private func completeOnboarding() {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let currentBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        DefaultSettingsStore.shared.set(.lastRunVersion, value: currentVersion)
        DefaultSettingsStore.shared.set(.lastRunBuild, value: currentBuild)
        DefaultSettingsStore.shared.set(.hasCompletedOnboarding, value: true)
        onComplete()
    }

    /// The shared page header. Every step uses it so the icon, title and subtitle sit at the same
    /// place and size on every page.
    private func stepHero(icon: Image, title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil) -> some View {
        VStack(spacing: 6) {
            icon
                .renderingMode(.template)
                .symbolRenderingMode(.hierarchical)
                .resizable()
                .scaledToFit()
                .frame(width: 42, height: 42)
                .foregroundStyle(Color.accentColor)
                .padding(.bottom, 2)

            Text(title)
                .font(.title2.weight(.bold))

            if let subtitle {
                Text(subtitle)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 40, alignment: .top)
            }
        }
    }

    // MARK: - Screen 1: Welcome & Value Concept

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            stepHero(icon: Image(systemName: "cursorarrow.rays"), title: "Welcome to OpenClip", subtitle: "Select text anywhere to get instant actions.")

            // Realistic Selection & Floating Action Bar Mock
            VStack(spacing: 10) {
                VStack(spacing: 14) {
                    // Floating OpenClip Action Bar HUD
                    HStack(spacing: 6) {
                        // Calculated math result badge
                        HStack(spacing: 4) {
                            Image(systemName: "equal.circle.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.accentColor)
                            Text("1,590")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.primary)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4.5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.accentColor.opacity(0.14))
                        )

                        actionPill(icon: "doc.on.doc", label: "Copy")
                        actionPill(icon: "character.book.closed.fill", label: "Translate")
                        actionPill(icon: "speaker.wave.2.fill", label: "Speak")
                        actionPill(icon: "sparkle", label: "AI")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(SettingsDesignTokens.sectionCardBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)

                    // Mock Selected Text Line
                    HStack(spacing: 0) {
                        Text("Total estimate: ")
                            .font(.system(size: 13.5))
                            .foregroundColor(.secondary)
                        Text("1250 + 340")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.25))
                            )
                        Text(" USD for redesign")
                            .font(.system(size: 13.5))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(SettingsDesignTokens.sectionCardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(SettingsDesignTokens.sectionCardBorder, lineWidth: 1)
                )
            }
        }
    }

    private func actionPill(icon: String, label: LocalizedStringKey) -> some View {
        HStack(spacing: 3.5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            Text(label)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4.5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    // MARK: - Screen 2: Permission & Privacy

    private var permissionStep: some View {
        VStack(spacing: 18) {
            stepHero(icon: Image(systemName: "hand.raised.fill"), title: "Two quick permissions", subtitle: "Everything stays on your Mac.")
            VStack(spacing: 10) {
                permissionRow(
                    icon: "hand.raised.fill",
                    title: "Accessibility",
                    reason: "Read the text you select",
                    tag: "Required",
                    isGranted: permissionManager.isAccessibilityGranted,
                    isProminent: true,
                    buttonTitle: "Grant"
                ) { permissionManager.requestAccessibilityPermission() }

                permissionRow(
                    icon: "rectangle.dashed.badge.record",
                    title: "Screen Recording",
                    reason: "Capture text from your screen",
                    tag: "Optional",
                    isGranted: permissionManager.isScreenRecordingGranted,
                    isProminent: false,
                    buttonTitle: "Allow"
                ) {
                    didRequestScreenRecording = true
                    permissionManager.requestScreenRecordingPermission()
                }

                if didRequestScreenRecording && !permissionManager.isScreenRecordingGranted {
                    Text("Restart OpenClip to finish")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 5) {
                Image(systemName: "lock.fill")
                Text("Text stays on your Mac unless you use cloud AI.")
            }
            .font(.system(size: 11.5))
            .foregroundColor(.secondary)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: permissionManager.isAccessibilityGranted)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: permissionManager.isScreenRecordingGranted)
    }

    /// One permission, one row. Both permissions share this layout; `isProminent` only changes how
    /// loudly the action button asks, so the optional one reads as quieter, not as a footnote.
    private func permissionRow(icon: String, title: LocalizedStringKey, reason: LocalizedStringKey,
                               tag: LocalizedStringKey, isGranted: Bool, isProminent: Bool,
                               buttonTitle: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 18))
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.accentColor.opacity(0.14))
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 13.5, weight: .semibold))
                    Text(tag)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
                Text(reason)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 8)

            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.green)
            } else {
                Button(action: action) {
                    Text(buttonTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 14)
                        .frame(height: 26)
                        .settingsGlassCapsule(tint: isProminent ? Color.accentColor : nil)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(SettingsDesignTokens.sectionCardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(SettingsDesignTokens.sectionCardBorder, lineWidth: 1)
        )
    }

    // MARK: - Screen 3: Extensions (Curated Defaults)

    private var extensionsStep: some View {
        VStack(spacing: 12) {
            stepHero(icon: Image(systemName: "puzzlepiece.extension.fill"), title: "Essential Extensions")

            RecommendedExtensionsView()
        }
    }

    // MARK: - Screen 4: Live Interactive Payoff Sandbox

    private var doneStep: some View {
        VStack(spacing: 14) {
            stepHero(icon: Image("MenuBarIcon"), title: "Try it", subtitle: "Select any text below.")

            // One bordered box, large enough to select from comfortably.
            SandboxTextView(
                text: "Our team sync is Friday at 2:30pm — project budget is 1250 + 340. Check https://getopenclip.app for details.",
                fontSize: 16,
                onSelection: {
                    if !hasDetectedSelection {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            hasDetectedSelection = true
                        }
                    }
                }
            )
            .frame(height: 150)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(SettingsDesignTokens.sectionCardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(hasDetectedSelection ? Color.green.opacity(0.5) : Color.accentColor.opacity(0.35), lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            // Selection Feedback or Shortcut hint
            if hasDetectedSelection {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Nice, that's it.")
                        .font(.callout.weight(.medium))
                        .foregroundColor(.green)
                }
                .transition(.scale.combined(with: .opacity))
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "command")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text("Press ⌥⌘C anytime to open OpenClip manually.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}
