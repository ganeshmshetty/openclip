// LayaRuntimeTests.swift
// OpenClipTests
//
// The bridge protocol, the not-installed path, the provider's runner seam, the bridge's own
// self-test, and (opt-in) a real decision through the installed runtime.
import XCTest
@testable import Core
@testable import OpenClip

@MainActor
final class LayaRuntimeTests: XCTestCase {
    func testEnvelopeParsesEventsAndReplies() throws {
        guard case .event(let name, let fields)? = LayaBridgeEnvelope.parse(
            #"{"event":"ready","model":"english","device":"mps","load_ms":1234}"#
        ) else { return XCTFail("expected an event") }
        XCTAssertEqual(name, "ready")
        XCTAssertEqual(fields[string: "model"], "english")
        XCTAssertEqual(fields[string: "device"], "mps")
        XCTAssertEqual(fields[int: "load_ms"], 1234)

        guard case .reply(let id, let response?, nil)? = LayaBridgeEnvelope.parse(
            #"{"id":7,"response":{"answers":[{"id":"q","type":"noul","noul":true,"confidence":0.9,"probabilities":{"true":0.9,"false":0.1}}],"confidence":0.9,"latency_ms":31}}"#
        ) else { return XCTFail("expected a reply") }
        XCTAssertEqual(id, 7)
        let parsed = try DecisionResponseParser.parse(response)
        XCTAssertEqual(parsed.answers.first?.value, .noul(true))
        XCTAssertEqual(parsed.answers.first?.probabilities["true"], 0.9)
        XCTAssertEqual(parsed.confidence, 0.9)

        guard case .reply(let errorID, nil, let error?)? = LayaBridgeEnvelope.parse(#"{"id":8,"error":"boom"}"#) else {
            return XCTFail("expected an error reply")
        }
        XCTAssertEqual(errorID, 8)
        XCTAssertEqual(error, "boom")

        XCTAssertNil(LayaBridgeEnvelope.parse("not json"))
        XCTAssertNil(LayaBridgeEnvelope.parse(#"{"noise":1}"#))
    }

    func testRuntimeWithoutEnvironmentIsNotInstalledAndRefusesDecisions() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("laya-\(UUID().uuidString)")
        let runtime = LayaRuntime(directory: directory, idleTimeout: 1)
        XCTAssertFalse(runtime.isInstalled)
        XCTAssertEqual(runtime.status, .notInstalled)

        do {
            _ = try await runtime.decide(Data("{}".utf8), model: "english")
            XCTFail("expected providerUnavailable")
        } catch let error as DecisionError {
            XCTAssertEqual(error, .providerUnavailable(LayaRuntime.notInstalledMessage))
        } catch {
            XCTFail("unexpected error \(error)")
        }

        let provider = LayaDecisionProvider(model: "english", runtime: runtime)
        let availability = await provider.availability()
        XCTAssertEqual(availability, .unavailable(reason: LayaRuntime.notInstalledMessage))
    }

    func testProviderUsesInjectedRunnerAndParsesBridgeShapedReply() async throws {
        let runtime = LayaRuntime(directory: FileManager.default.temporaryDirectory.appendingPathComponent("laya-\(UUID().uuidString)"))
        let provider = LayaDecisionProvider(model: "multilingual", runtime: runtime)
        provider.runner = { model, payload in
            XCTAssertEqual(model, "multilingual")
            let request = try JSONSerialization.jsonObject(with: payload) as? [String: Any]
            XCTAssertEqual(request?["state"] as? String, "wire it today")
            let questions = request?["questions"] as? [[String: Any]]
            XCTAssertEqual(questions?.first?["id"] as? String, "urgent")
            XCTAssertEqual(questions?.first?["type"] as? String, "noul")
            return Data(#"{"answers":[{"id":"urgent","type":"noul","noul":true,"confidence":0.93,"probabilities":{"true":0.93,"false":0.07}}],"confidence":0.93,"latency_ms":31,"device":"mps"}"#.utf8)
        }
        let request = DecisionQuestionPacker.pack(
            state: "wire it today",
            questions: [.noul(id: "urgent", prompt: "Urgent?")],
            toolID: "t"
        )
        let response = try await provider.decide(request)
        XCTAssertEqual(response.answers.first?.value, .noul(true))
        XCTAssertEqual(response.answers.first?.confidence, 0.93)
        XCTAssertEqual(response.answers.first?.probabilities["false"], 0.07)
    }

    /// The bridge's --selftest exercises its OpenClip <-> Laya schema mapping with a fake agent, so
    /// it runs with any python3 and needs neither torch nor a model.
    func testBridgeSelfTestPassesWithSystemPython() throws {
        guard let script = LayaRuntime.bridgeScriptURL else {
            throw XCTSkip("laya_bridge.py is not bundled in the test host")
        }
        let candidates = ["/usr/bin/python3", "/opt/homebrew/bin/python3", "/usr/local/bin/python3"]
        guard let python = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw XCTSkip("no python3 on this machine")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = [script.path, "--selftest"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, output)
        XCTAssertTrue(output.contains("\"ok\": true"), output)
    }

    /// End to end through the environment in ~/.openclip/laya. Opt in with OPENCLIP_LAYA_E2E=1
    /// (TEST_RUNNER_OPENCLIP_LAYA_E2E=1 for xcodebuild); loads the model, so it takes a while.
    func testRealBridgeDecidesThroughInstalledRuntime() async throws {
        guard ProcessInfo.processInfo.environment["OPENCLIP_LAYA_E2E"] == "1" else {
            throw XCTSkip("set OPENCLIP_LAYA_E2E=1 to decide through the installed Laya runtime")
        }
        let runtime = LayaRuntime(directory: Constants.layaDirectory, idleTimeout: 0)
        guard runtime.isInstalled, LayaRuntime.bridgeScriptURL != nil else {
            throw XCTSkip("Laya runtime is not installed on this machine")
        }
        defer { runtime.stopBridge() }

        let provider = LayaDecisionProvider(model: "english", runtime: runtime)
        let options = ["billing", "engineering", "sales"]
        let request = DecisionQuestionPacker.pack(
            state: "Hi team, the client threatened to cancel unless the duplicate invoice is refunded today.",
            questions: [
                .noul(id: "urgent", prompt: "Does this message communicate time pressure?"),
                .choice(id: "dept", prompt: "Which team should handle this?", options: options),
                .score(id: "anger", prompt: "How upset does the sender sound?", min: 1, max: 5),
            ],
            toolID: "e2e"
        )

        let coldStart = Date()
        let first = try await provider.decide(request)
        let coldMS = Int(Date().timeIntervalSince(coldStart) * 1000)

        XCTAssertEqual(first.answers.count, 3)
        guard case .noul? = first.answer(for: "urgent")?.value else { return XCTFail("urgent should be a yes/no answer") }
        guard case .choice(let labels)? = first.answer(for: "dept")?.value, labels.count == 1 else {
            return XCTFail("dept should be a single choice")
        }
        XCTAssertTrue(options.contains(labels[0]), "choice \(labels[0]) must be one of the options")
        guard case .score(let level)? = first.answer(for: "anger")?.value else { return XCTFail("anger should be a score") }
        XCTAssertTrue((1...5).contains(level))
        for answer in first.answers {
            let confidence = try XCTUnwrap(answer.confidence)
            XCTAssertTrue((0...1).contains(confidence))
        }
        guard case .running(let model, let device) = runtime.status else {
            return XCTFail("runtime should be running after a decision, was \(runtime.status)")
        }
        XCTAssertEqual(model, "english")
        XCTAssertFalse(device.isEmpty)

        let warmStart = Date()
        let second = try await provider.decide(request)
        let warmMS = Int(Date().timeIntervalSince(warmStart) * 1000)
        XCTAssertEqual(second.answers.count, 3)
        XCTAssertLessThan(warmMS, 5000, "a warm decision should be fast")
        print("laya e2e: cold \(coldMS) ms (includes model load), warm \(warmMS) ms, answers \(first.answers.map(\.value.displayLabel))")
    }
}
