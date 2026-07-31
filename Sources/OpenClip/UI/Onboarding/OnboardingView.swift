import SwiftUI
import AppKit

@MainActor
public struct OnboardingView: View {
    @ObservedObject private var permissionManager = PermissionManager.shared
    public var onComplete: @MainActor () -> Void

    public init(onComplete: @escaping @MainActor () -> Void) {
        self.onComplete = onComplete
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── App icon + name ──────────────────────────────────────────────
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 2) {
                    Text("OpenClip")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Text selection tool for macOS")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.bottom, 24)

            // ── How it works ─────────────────────────────────────────────────
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

            // ── Permission ───────────────────────────────────────────────────
            Divider()
                .padding(.vertical, 20)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accessibility Access")
                            .font(.system(size: 13, weight: .medium))
                        Text("Required to detect which text you've selected.")
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

                        Button("Re-check") {
                            permissionManager.checkStatus()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)

                        Button("Reset & Relaunch") {
                            permissionManager.resetTCCAndRelaunch()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .help("Use this if you already enabled access but OpenClip doesn't detect it yet.")
                    }
                }
            }

            // ── Footer ───────────────────────────────────────────────────────
            Divider()
                .padding(.top, 20)
                .padding(.bottom, 14)

            HStack {
                Text("Runs 100% locally — no data leaves your Mac.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                    onComplete()
                } label: {
                    Text("Get Started")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!permissionManager.isAccessibilityGranted)
            }
        }
        .padding(28)
        .frame(width: 460)
        .fixedSize(horizontal: true, vertical: true)
        .onAppear  { permissionManager.startMonitoring() }
        .onDisappear { permissionManager.stopMonitoring() }
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
