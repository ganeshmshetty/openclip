// SystemRegionSelector.swift
// OpenClip
//
// Delegates interactive region selection to Apple's screencapture tool. The system process owns
// the crosshair, the non-activating overlay, the event grab, multi-display geometry, and Space
// behavior, so OpenClip never has to manipulate the cursor or take the mouse itself.
import AppKit
import CoreGraphics
import ImageIO

/// Runs `/usr/sbin/screencapture -i` and returns the selected image.
@MainActor
final class SystemRegionSelector {
    struct Selection {
        let image: CGImage
        /// AppKit screen coordinates of the pointer when the selection finished.
        let releasePoint: CGPoint
    }

    enum SelectionError: Error {
        case unreadableImage
    }

    private var process: Process?

    /// Returns nil when the user cancels (the system tool exits non-zero).
    func select() async throws -> Selection? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("openclip-capture-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", "-t", "png", url.path]
        self.process = process
        defer { self.process = nil }
        let status = try await run(process)
        guard status == 0 else { return nil }

        let releasePoint = NSEvent.mouseLocation
        guard let image = Self.loadImage(url) else {
            throw SelectionError.unreadableImage
        }
        return Selection(image: image, releasePoint: releasePoint)
    }

    func cancel() {
        process?.terminate()
        process = nil
    }

    private func run(_ process: Process) async throws -> Int32 {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let gate = ResumeGate(continuation)
                process.terminationHandler = { finished in
                    gate.resume(returning: finished.terminationStatus)
                }
                if Task.isCancelled {
                    process.terminationHandler = nil
                    gate.resume(throwing: CancellationError())
                    return
                }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    gate.resume(throwing: error)
                }
            }
        } onCancel: {
            process.terminate()
        }
    }

    /// `CGImageSourceCreateImageAtIndex` may decode lazily from the file. Copy the pixels into an
    /// owned bitmap so the temp file can be removed as soon as the selection returns.
    nonisolated static func loadImage(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }
}

/// The process termination handler runs on a background queue; resume exactly once.
private final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Int32, Error>?

    init(_ continuation: CheckedContinuation<Int32, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: Int32) {
        let continuation = takeContinuation()
        continuation?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        let continuation = takeContinuation()
        continuation?.resume(throwing: error)
    }

    private func takeContinuation() -> CheckedContinuation<Int32, Error>? {
        lock.withLock {
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
    }
}
