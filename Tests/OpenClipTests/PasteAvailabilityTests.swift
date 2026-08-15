import XCTest
import AppKit
import Core
@testable import OpenClip

/// The unified paste-availability decision: the per-app `denyPaste` rule wins over the live AX
/// probe, and every consumer (bar/card gating and the delivery re-decision) reads the same answer.
final class PasteAvailabilityTests: XCTestCase {

    // MARK: - Pure effective() decision

    func testDenyPasteWinsOverProbe() {
        let policy = AppPolicyContext(denyPaste: true)
        XCTAssertEqual(PasteAvailability.effective(policy: policy, probe: true), false)
        XCTAssertEqual(PasteAvailability.effective(policy: policy, probe: false), false)
        XCTAssertEqual(PasteAvailability.effective(policy: policy, probe: nil), false)
    }

    func testDefaultFallsThroughToProbe() {
        XCTAssertEqual(PasteAvailability.effective(policy: .default, probe: true), true)
        XCTAssertEqual(PasteAvailability.effective(policy: .default, probe: false), false)
        XCTAssertEqual(PasteAvailability.effective(policy: .default, probe: nil), nil)
    }

    func testNeedsProbeOnlyWithoutDenyPasteRule() {
        XCTAssertTrue(PasteAvailability.needsProbe(policy: .default))
        XCTAssertFalse(PasteAvailability.needsProbe(policy: AppPolicyContext(denyPaste: true)))
    }

    // MARK: - The unified value drives the delivery re-decision (Terminal escape hatch)

    func testDenyPastePolicyForcesCopyThroughUnifiedValue() {
        let canPaste = PasteAvailability.effective(policy: AppPolicyContext(denyPaste: true), probe: true) ?? false
        let (result, _) = ActionResultDelivery.resolve(raw: .paste("hello"), clickIntent: .primary, canPaste: canPaste, delivery: .none)
        guard case .copy(let text) = result else { return XCTFail("denyPaste must force a copy") }
        XCTAssertEqual(text, "hello")
    }

    // MARK: - Wiring: the controller threads the policy through preparePasteProbe, so gating honors rules

    /// A probe that "would happily paste" must still gate to `false` under a denyPaste rule — the
    /// rule is applied before the bar renders, not as a separate hand-edited decision.
    @MainActor
    func testPreparePasteProbeHonorsDenyPasteRule() async {
        let controller = PopupWindowController(pasteProbe: PolicyAwareFixedProbe(result: true))
        let denyProbe = controller.preparePasteProbe(for: nil, policy: AppPolicyContext(denyPaste: true))
        let denyValue = await denyProbe.value
        XCTAssertEqual(denyValue, false, "denyPaste rule must override a probe that says paste works")
    }
}

/// Applies the same rule-first unification the real probe does, so controller wiring is exercised
/// deterministically without AX.
private struct PolicyAwareFixedProbe: PasteAvailabilityProbing {
    let result: Bool?

    func canPaste(in app: NSRunningApplication?, policy: AppPolicyContext) async -> Bool? {
        PasteAvailability.effective(policy: policy, probe: result)
    }
}