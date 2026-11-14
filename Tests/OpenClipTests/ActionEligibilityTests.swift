// ActionEligibilityTests.swift
// OpenClipTests
//
// The capability policy: what an action needs, what an effect needs, and when a result degrades
// instead of landing.
import XCTest
import Core
@testable import OpenClip

final class ActionEligibilityTests: XCTestCase {
    private func selection(
        text: String = "hello",
        source: SelectionSource = .selection,
        editable: Bool? = true,
        paste: Bool? = true
    ) -> SelectionContext {
        SelectionContext(
            text: text,
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            source: source,
            isEditable: editable,
            pasteTargetAvailable: paste
        )
    }

    private func capabilities(
        _ selection: SelectionContext,
        live: CapabilityAvailability = .unknown
    ) -> TargetCapabilities {
        selection.targetCapabilities(targetIsLive: live)
    }

    // MARK: - Declared needs

    func testDeclaredNeedsFollowTheInputRequirement() {
        XCTAssertEqual(ActionEligibility.needs(for: ActionRequirements(input: .optional)), [])
        XCTAssertEqual(ActionEligibility.needs(for: ActionRequirements(input: .text)), [.text])
        XCTAssertEqual(
            ActionEligibility.needs(for: ActionRequirements(input: .liveSelection)),
            [.text, .liveSelection]
        )
        XCTAssertEqual(
            ActionEligibility.needs(for: ActionRequirements(input: .editableSelection)),
            [.text, .liveSelection, .editableText]
        )
        XCTAssertEqual(
            ActionEligibility.needs(for: ActionRequirements(input: .text, requiresPasteTarget: true)),
            [.text, .pasteDestination]
        )
    }

    func testUnknownCapabilitiesFailDeclaredRequirements() {
        let unknownEditable = selection(editable: nil)
        XCTAssertFalse(ActionEligibility.isSatisfied(
            requirements: ActionRequirements(input: .editableSelection),
            selection: unknownEditable,
            capabilities: capabilities(unknownEditable)
        ))
        let unknownPaste = selection(paste: nil)
        XCTAssertFalse(ActionEligibility.isSatisfied(
            requirements: ActionRequirements(input: .text, requiresPasteTarget: true),
            selection: unknownPaste,
            capabilities: capabilities(unknownPaste)
        ))
    }

    func testReadOnlySelectionDoesNotSatisfyEditableSelection() {
        let readOnly = selection(editable: false)
        XCTAssertFalse(ActionEligibility.isSatisfied(
            requirements: ActionRequirements(input: .editableSelection),
            selection: readOnly,
            capabilities: capabilities(readOnly)
        ))
    }

    func testClipboardInputNeverSatisfiesLiveSelection() {
        let clipboard = selection(source: .clipboard)
        XCTAssertFalse(ActionEligibility.isSatisfied(
            requirements: ActionRequirements(input: .liveSelection),
            selection: clipboard,
            capabilities: capabilities(clipboard)
        ))
    }

    func testConfirmedTargetLossFailsEvenWhenCapabilitiesAreAvailable() {
        let editable = selection()
        XCTAssertFalse(ActionEligibility.isSatisfied(
            [.editableText],
            selection: editable,
            capabilities: capabilities(editable, live: .unavailable),
            unknownSatisfies: true
        ))
    }

    // MARK: - Effect requirements

    func testEffectRequirementsArePayloadAware() {
        XCTAssertEqual(ActionEligibility.requirement(for: .paste("a")), .textInsertion)
        XCTAssertEqual(ActionEligibility.requirement(for: .cut("a")), .textInsertion)
        XCTAssertEqual(ActionEligibility.requirement(for: .simulatePaste), .pasteboardPaste)
        XCTAssertEqual(
            ActionEligibility.requirement(for: .pasteContent(RichPasteboardPayload(plainText: "a"))),
            .textInsertion
        )
        XCTAssertEqual(
            ActionEligibility.requirement(for: .pasteContent(RichPasteboardPayload(flavors: [
                RichPasteboardFlavor(type: "public.file-url", data: Data())
            ]))),
            .pasteboardPaste
        )
        XCTAssertEqual(
            ActionEligibility.requirement(for: .sequence([.copy("a"), .simulatePaste])),
            .pasteboardPaste
        )
    }

    // MARK: - Degradation

    func testUnknownInsertionDegradesTextButNotExplicitCopy() {
        let target = TargetCapabilities(textInsertion: .unknown, pasteboardPaste: .available)
        guard case .copy("a") = ActionEligibility.degrade(.paste("a"), capabilities: target) else {
            return XCTFail("text paste must not gamble on the paste menu")
        }
        guard case .copy("b") = ActionEligibility.degrade(.copy("b"), capabilities: target) else {
            return XCTFail("copy is already lossless")
        }
    }

    func testConfirmedInsertionKeepsTextPaste() {
        let target = TargetCapabilities(textInsertion: .available, pasteboardPaste: .unavailable)
        guard case .paste("a") = ActionEligibility.degrade(.paste("a"), capabilities: target) else {
            return XCTFail("editability is the evidence text insertion needs")
        }
    }

    func testSimulatePasteIsDroppedOnlyWhenTheDestinationIsConfirmedUnavailable() {
        guard case .none = ActionEligibility.degrade(
            .simulatePaste,
            capabilities: TargetCapabilities(pasteboardPaste: .unavailable)
        ) else { return XCTFail("confirmed no-paste target must not receive Cmd+V") }

        guard case .simulatePaste = ActionEligibility.degrade(
            .simulatePaste,
            capabilities: TargetCapabilities(pasteboardPaste: .unknown)
        ) else { return XCTFail("a timed-out probe keeps legacy behavior") }
    }

    func testSequenceDegradesPerItem() {
        let target = TargetCapabilities(textInsertion: .unavailable, pasteboardPaste: .available)
        guard case .sequence(let items) = ActionEligibility.degrade(
            .sequence([.paste("a"), .openURL(URL(string: "https://example.com")!), .copy("b")]),
            capabilities: target
        ) else { return XCTFail("expected a sequence") }
        guard case .copy("a") = items[0] else { return XCTFail("paste must copy") }
        guard case .openURL = items[1] else { return XCTFail("non-paste effects pass through") }
        guard case .copy("b") = items[2] else { return XCTFail("copy stays copy") }
    }

    func testDenyPasteForcesBothPastePathsToCopy() {
        var target = TargetCapabilities(textInsertion: .available, pasteboardPaste: .available)
        target.applyDenyPaste(AppPolicyContext(denyPaste: true))
        XCTAssertEqual(target.textInsertion, .unavailable)
        XCTAssertEqual(target.pasteboardPaste, .unavailable)

        var untouched = TargetCapabilities(textInsertion: .available, pasteboardPaste: .available)
        untouched.applyDenyPaste(.default)
        XCTAssertEqual(untouched.textInsertion, .available)
    }
}
