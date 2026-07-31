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
        VStack(spacing: 24) {
            // Header Hero
            VStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 84, height: 84)
                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                
                Text("Welcome to OpenClip")
                    .font(.system(size: 26, weight: .bold))
                
                Text("The open-source text selection action tool for macOS")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 12)
            
            // Features Card
            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(
                    icon: "text.cursor",
                    color: .blue,
                    title: "Instant Text Detection",
                    description: "Select text in any application and OpenClip brings up actions automatically."
                )
                
                FeatureRow(
                    icon: "sparkles",
                    color: .purple,
                    title: "Extensions & Built-in Tools",
                    description: "Copy, Paste, Search, run Shell Scripts, or launch PopClip extensions seamlessly."
                )
                
                FeatureRow(
                    icon: "lock.shield",
                    color: .green,
                    title: "100% Private & Open Source",
                    description: "Runs entirely on your local machine with strict sandboxing and zero tracking."
                )
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.04)))
            
            // Permission Card
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Accessibility Permission")
                            .font(.system(size: 15, weight: .semibold))
                        Text(permissionManager.isAccessibilityGranted ? "Permission granted! OpenClip is ready to use." : "Required for OpenClip to detect text selection across apps.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    
                    HStack(spacing: 6) {
                        Circle()
                            .fill(permissionManager.isAccessibilityGranted ? Color.green : Color.orange)
                            .frame(width: 10, height: 10)
                        Text(permissionManager.isAccessibilityGranted ? "Granted" : "Required")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(permissionManager.isAccessibilityGranted ? .green : .orange)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
                }
                
                if !permissionManager.isAccessibilityGranted {
                    Button(action: {
                        permissionManager.requestAccessibilityPermission()
                    }, label: {
                        HStack {
                            Image(systemName: "hand.tap.fill")
                            Text("Grant Accessibility Permission")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    })
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(permissionManager.isAccessibilityGranted ? Color.green.opacity(0.4) : Color.orange.opacity(0.4), lineWidth: 1.5)
                    .background(RoundedRectangle(cornerRadius: 14).fill(permissionManager.isAccessibilityGranted ? Color.green.opacity(0.05) : Color.orange.opacity(0.05)))
            )
            
            Spacer()
            
            // Footer Action
            HStack {
                Spacer()
                Button(action: {
                    UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                    onComplete()
                }, label: {
                    Text(permissionManager.isAccessibilityGranted ? "Get Started" : "Continue")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 6)
                })
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!permissionManager.isAccessibilityGranted)
            }
        }
        .padding(24)
        .frame(width: 520, height: 560)
        .onAppear {
            permissionManager.startMonitoring()
        }
        .onDisappear {
            permissionManager.stopMonitoring()
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
                .frame(width: 32, height: 32)
                .background(Circle().fill(color.opacity(0.15)))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
