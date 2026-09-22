// LayaRuntimeSection.swift
// OpenClip
//
// Preferences → Decisions → Provider rows for Laya: model choice, runtime status, and the
// two steps behind it: Download / Delete puts the environment and model on the Mac, Start / Stop
// runs the model. Backed by `LayaRuntime`.
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
            runtime.stop()
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
            case .notDownloaded, .failed:
                Button(String(localized: "Download")) {
                    Task { await runtime.download(model: model) }
                }
                if FileManager.default.fileExists(atPath: runtime.directory.path) {
                    Spacer()
                    removeButtons
                }
            case .downloading, .starting:
                EmptyView()
            case .downloaded:
                Button(String(localized: "Start")) {
                    Task { await runtime.start(model: model) }
                }
                Spacer()
                removeButtons
            case .running:
                Button(String(localized: "Stop")) { runtime.stop() }
                Spacer()
                removeButtons
            }
        }

        Text(String(localized: "Runs on this Mac; nothing leaves it. Download fetches PyTorch and the model (about 1.5 GB) into ~/.openclip/laya. Once started, the model stops on its own 10 minutes after the last decision."))
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var removeButtons: some View {
        if confirmingRemove {
            Button(String(localized: "Cancel")) { confirmingRemove = false }
            Button(String(localized: "Delete"), role: .destructive) {
                runtime.delete()
                confirmingRemove = false
            }
        } else {
            Button(String(localized: "Delete…"), role: .destructive) { confirmingRemove = true }
        }
    }

    private var runtimeFailed: Bool {
        if case .failed = runtime.status { return true }
        return false
    }

    private var statusText: String {
        switch runtime.status {
        case .notDownloaded:
            return String(localized: "Not downloaded")
        case .downloading(let step):
            return step
        case .downloaded:
            return String(localized: "Downloaded; not running")
        case .starting(let phase):
            return phase
        case .running(let model, let device):
            return String(localized: "Running \(model) on \(device)")
        case .failed(let message):
            return message
        }
    }
}
