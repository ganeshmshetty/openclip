// VisionTextRecognizer.swift
// OpenClip
//
// Configures the on-device Vision text request and loads its model before the user needs it.
import CoreGraphics
import CoreText
import Foundation
import Core
import Vision

/// Loads the Vision text model ahead of Capture Text; see `docs/architecture/known-debt.md`.
final class VisionTextRecognizer: @unchecked Sendable {
    static let shared = VisionTextRecognizer()

    private static let warmUpMaxAge: TimeInterval = 10 * 60

    private let lock = NSLock()
    private var lastWarmUp: Date?
    private var warmUpRunning = false

    func warmUpIfStale() {
        let shouldWarm = lock.withLock {
            guard !warmUpRunning else { return false }
            if let lastWarmUp, Date().timeIntervalSince(lastWarmUp) < Self.warmUpMaxAge {
                return false
            }
            warmUpRunning = true
            return true
        }
        guard shouldWarm else { return }
        guard let image = Self.warmUpImage else {
            lock.withLock { warmUpRunning = false }
            return
        }

        Task.detached(priority: .utility) { [self] in
            let started = Date()
            let succeeded = (try? await Self.recognize(image)) != nil
            let milliseconds = Int(Date().timeIntervalSince(started) * 1000)
            Log.selection.info("Capture Text: Vision warm-up finished in \(milliseconds, privacy: .public)ms succeeded=\(succeeded, privacy: .public)")
            finishWarmUp(succeeded: succeeded)
        }
    }

    private func finishWarmUp(succeeded: Bool) {
        lock.withLock {
            if succeeded { lastWarmUp = Date() }
            warmUpRunning = false
        }
    }

    static func recognize(_ image: CGImage) async throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        let box = RecognitionRequestBox(request: request)
        // A detached task does not inherit cancellation, so cancel the Vision request itself.
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                try VNImageRequestHandler(cgImage: image).perform([box.request])
                let lines = (box.request.results ?? []).compactMap { observation in
                    observation.topCandidates(1).first.map {
                        RecognizedTextLayout.Line(text: $0.string, box: observation.boundingBox)
                    }
                }
                return RecognizedTextLayout.join(lines)
            }.value
        } onCancel: {
            box.request.cancel()
        }
    }

    private static let warmUpImage: CGImage? = makeWarmUpImage()

    private static func makeWarmUpImage() -> CGImage? {
        let width = 720
        let height = 140
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = CTFontCreateWithName("Helvetica" as CFString, 48, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: "OpenClip captures text", attributes: attributes)
        )
        context.textPosition = CGPoint(x: 16, y: 44)
        CTLineDraw(line, context)
        return context.makeImage()
    }
}

/// Vision's request class predates Sendable; cancelling it from another thread is supported.
private final class RecognitionRequestBox: @unchecked Sendable {
    let request: VNRecognizeTextRequest
    init(request: VNRecognizeTextRequest) { self.request = request }
}
