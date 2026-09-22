// LayaRuntimeSection.swift
// OpenClip
//
// Preferences → Decisions → Provider rows for Laya: model choice, runtime status, and the
// Install / Prepare / Unload / Remove actions backed by `LayaRuntime`.
import SwiftUI
import Core

@MainActor
struct LayaRuntimeSection: View {
    @Binding var model: String
    @ObservedObject private var runtime = LayaRuntime.shared
    @State private var confirmingRemove = false

    var body: some View {
        Picker(String(localized: "Model"), selection: $model) {
            ForEach(LayaRuntime.models, id: \.id) { entry in
                Text(entry.title).tag(entry.id)
            }
        }
        .disabled(runtime.status.isBusy)
        .onChange(of: model) { _, _ in
            // The next decision (or Prepare Model) loads the newly chosen checkpoint.
            runtime.stopBridge()
        }

        LabeledContent(String(localized: "Runtime")) {
            HStack(spacing: 6) {
                if runtime.status.isBusy {
                    ProgressView().controlSize(.small)
                }
                Text(statusText)
                    .foregroundStyle(runtimeFailed ? Color.red : Color.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.trailing)
            }
        }

        if runtime.status.isBusy, !runtime.lastLogLine.isEmpty, runtime.lastLogLine != statusText {
            Text(runtime.lastLogLine)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
        }

        HStack {
            switch runtime.status {
            case .notInstalled, .failed:
                Button(String(localized: "Install Laya")) {
                    Task { await runtime.install(model: model) }
                }
                if FileManager.default.fileExists(atPath: runtime.directory.path) {
                    Spacer()
                    removeButtons
                }
            case .installing, .starting:
                EmptyView()
            case .installed, .running:
                Button(String(localized: "Prepare Model")) {
                    Task { await runtime.prepare(model: model) }
                }
                if case .running = runtime.status {
                    Button(String(localized: "Unload")) { runtime.stopBridge() }
                }
                Spacer()
                removeButtons
            }
        }

        Text(String(localized: "Runs on this Mac; nothing leaves it. Install downloads PyTorch and the model (about 1.5 GB) into ~/.openclip/laya. The model stays loaded for 10 minutes after the last decision."))
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var removeButtons: some View {
        if confirmingRemove {
            Button(String(localized: "Cancel")) { confirmingRemove = false }
            Button(String(localized: "Remove"), role: .destructive) {
                runtime.uninstall()
                confirmingRemove = false
            }
        } else {
            Button(String(localized: "Remove…"), role: .destructive) { confirmingRemove = true }
        }
    }

    private var runtimeFailed: Bool {
        if case .failed = runtime.status { return true }
        return false
    }

    private var statusText: String {
        switch runtime.status {
        case .notInstalled:
            return String(localized: "Not installed")
        case .installing(let step):
            return step
        case .installed:
            return String(localized: "Installed; the model loads on first use")
        case .starting(let phase):
            return phase
        case .running(let model, let device):
            return String(localized: "Running \(model) on \(device)")
        case .failed(let message):
            return message
        }
    }
}
