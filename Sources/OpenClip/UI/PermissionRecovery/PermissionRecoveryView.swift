// PermissionRecoveryView.swift
// OpenClip
//
// Compact, polished permission recovery view presented when an existing installation has been updated
// or reinstalled, or when Accessibility permissions have been revoked.
import SwiftUI
import AppKit
import Core

@MainActor
public struct PermissionRecoveryView: View {
    @ObservedObject private var permissionManager = PermissionManager.shared
    public let isUpdate: Bool
    public let onComplete: @MainActor () -> Void
    public let onDismiss: @MainActor () -> Void

    @State private var hasAutoDismissed = false
    @State private var autoDismissTask: Task<Void, Never>?

    public init(
        isUpdate: Bool,
        onComplete: @escaping @MainActor () -> Void,
        onDismiss: @escaping @MainActor () -> Void
    ) {
        self.isUpdate = isUpdate
        self.onComplete = onComplete
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Header Hero
            VStack(spacing: 8) {
                Image(systemName: permissionManager.isAccessibilityGranted ? "checkmark.shield.fill" : (isUpdate ? "arrow.triangle.2.circlepath.circle.fill" : "hand.raised.square.fill"))
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 40))
                    .foregroundStyle(permissionManager.isAccessibilityGranted ? Color.green : Color.accentColor)

                Text(isUpdate ? String(localized: "OpenClip Has Been Updated") : String(localized: "Accessibility Access Required"))
                    .font(.title3.weight(.bold))

                Text(isUpdate
                     ? String(localized: "macOS requires re-enabling Accessibility to continue detecting text selections.")
                     : String(localized: "OpenClip needs Accessibility access to detect selected text and display action bars."))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
            }

            // Action / Status
            if permissionManager.isAccessibilityGranted {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Accessibility Permission Granted")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.green)
                }
                .padding(.vertical, 4)
                .transition(.opacity.combined(with: .scale))
            } else {
                VStack(spacing: 8) {
                    Button("Open System Settings…") {
                        permissionManager.requestAccessibilityPermission()
                    }
                    .buttonStyle(MacPrimaryButtonStyle())

                    Text("Flip the switch next to OpenClip to ON in System Settings.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)

            // Bottom bar
            HStack {
                Button("Later") {
                    onDismiss()
                }
                .buttonStyle(MacSecondaryButtonStyle())

                Spacer()
            }
        }
        .padding(22)
        .frame(width: 440, height: 260)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            permissionManager.startMonitoring()
        }
        .onDisappear {
            autoDismissTask?.cancel()
            autoDismissTask = nil
            permissionManager.stopMonitoring()
        }
        .onChange(of: permissionManager.isAccessibilityGranted) { _, isGranted in
            if isGranted && !hasAutoDismissed {
                hasAutoDismissed = true
                autoDismissTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s visual confirmation
                    guard !Task.isCancelled else { return }
                    onComplete()
                }
            }
        }
    }
}
