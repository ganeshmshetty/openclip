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
        ScrollView {
            VStack(spacing: 20) {

                // ── Header ──────────────────────────────────────────────────
                VStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 72, height: 72)
                        .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)

                    Text("Welcome to OpenClip")
                        .font(.system(size: 24, weight: .bold))

                    Text("The open-source text selection tool for macOS")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 16)

                // ── Feature rows ────────────────────────────────────────────
                VStack(alignment: .leading, spacing: 14) {
                    FeatureRow(icon: "text.cursor",   color: .blue,   title: "Instant Detection",  description: "Select any text — OpenClip appears immediately, no shortcuts needed.")
                    FeatureRow(icon: "sparkles",      color: .purple, title: "Extensions & Tools", description: "Copy, Search, run Shell scripts, or load PopClip extensions.")
                    FeatureRow(icon: "lock.shield",   color: .green,  title: "100 % Private",      description: "Runs entirely on your Mac. Zero telemetry, zero tracking.")
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))

                // ── Permission card ─────────────────────────────────────────
                VStack(spacing: 10) {
                    // Status row
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Accessibility Permission")
                                .font(.system(size: 14, weight: .semibold))
                            Text(permissionManager.isAccessibilityGranted
                                 ? "Granted — OpenClip is ready!"
                                 : "Required to detect selections in other apps.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        HStack(spacing: 5) {
                            Circle()
                                .fill(permissionManager.isAccessibilityGranted ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(permissionManager.isAccessibilityGranted ? "Granted" : "Required")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(permissionManager.isAccessibilityGranted ? .green : .orange)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.06)))
                    }

                    if !permissionManager.isAccessibilityGranted {
                        // Open Settings
                        Button {
                            permissionManager.requestAccessibilityPermission()
                        } label: {
                            Label("Open Accessibility Settings", systemImage: "hand.tap.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        // Re-check + Relaunch row
                        HStack(spacing: 8) {
                            Button {
                                permissionManager.checkStatus()
                            } label: {
                                Label("Re-check", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button {
                                permissionManager.relaunchApp()
                            } label: {
                                Label("Relaunch App", systemImage: "power")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Spacer()

                            Text("Grant in Settings, then Re-check or Relaunch.")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            permissionManager.isAccessibilityGranted ? Color.green.opacity(0.45) : Color.orange.opacity(0.45),
                            lineWidth: 1.5
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(permissionManager.isAccessibilityGranted ? Color.green.opacity(0.05) : Color.orange.opacity(0.05))
                        )
                )

                // ── Get Started button ──────────────────────────────────────
                HStack {
                    Spacer()
                    Button {
                        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                        onComplete()
                    } label: {
                        Text(permissionManager.isAccessibilityGranted ? "Get Started →" : "Get Started →")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 28)
                            .padding(.vertical, 7)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!permissionManager.isAccessibilityGranted)
                }
                .padding(.bottom, 16)
            }
            .padding(.horizontal, 24)
        }
        .frame(width: 500)
        .fixedSize(horizontal: true, vertical: true)   // let height be dynamic
        .onAppear  { permissionManager.startMonitoring() }
        .onDisappear { permissionManager.stopMonitoring() }
    }
}

// MARK: - Feature row
private struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(color)
                .frame(width: 30, height: 30)
                .background(Circle().fill(color.opacity(0.15)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
