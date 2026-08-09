// JavaScriptCanvasEngineTests.swift
// OpenClipTests

import XCTest
import JavaScriptCore
@testable import Core
@testable import OpenClip

final class JavaScriptCanvasEngineTests: XCTestCase {
    // 1. Counter mount & dispatch
    func testSyncCounterMountAndDispatch() async throws {
        let script = """
        const initialState = { count: 0 };
        const handlers = {
            increment: (state) => ({ count: state.count + 1 })
        };
        const ui = (state) => h('button', { title: 'Count: ' + state.count, handler: 'increment' });
        """
        let engine = JavaScriptCanvasEngine()
        let mountReq = CanvasMountRequest(input: "test", scriptCode: script)
        let mountRes = try await engine.mount(mountReq)

        XCTAssertEqual(mountRes.state["count"]?.numberValue, 0)
        guard case .button(let props) = mountRes.tree else {
            return XCTFail("Expected button tree root")
        }
        XCTAssertEqual(props.title, "Count: 0")

        let dispatchReq = CanvasDispatchRequest(
            event: CanvasEvent(kind: .tap, handler: "increment"),
            state: mountRes.state
        )
        let dispatchRes = try await engine.dispatch(dispatchReq)

        XCTAssertEqual(dispatchRes.state["count"]?.numberValue, 1)
        guard case .button(let updatedProps) = dispatchRes.tree else {
            return XCTFail("Expected button tree root")
        }
        XCTAssertEqual(updatedProps.title, "Count: 1")
    }

    // 2. TextField submit & change dispatch
    func testTextFieldSubmitAndChangeDispatch() async throws {
        let script = """
        const handlers = {
            update: (state, event) => ({ text: event.value })
        };
        const ui = (state) => h('textField', { id: 'field', value: state.text || '', onChange: 'update', onSubmit: 'update' });
        """
        let engine = JavaScriptCanvasEngine()
        let mountRes = try await engine.mount(CanvasMountRequest(input: "test", scriptCode: script))

        let changeReq = CanvasDispatchRequest(
            event: CanvasEvent(kind: .change, handler: "update", value: "hello", targetID: "field"),
            state: mountRes.state
        )
        let changeRes = try await engine.dispatch(changeReq)
        XCTAssertEqual(changeRes.state.string("text"), "hello")
        guard case .textField(let fieldProps) = changeRes.tree else {
            return XCTFail("Expected textField root")
        }
        XCTAssertEqual(fieldProps.value, "hello")

        let submitReq = CanvasDispatchRequest(
            event: CanvasEvent(kind: .submit, handler: "update", value: "world", targetID: "field"),
            state: changeRes.state
        )
        let submitRes = try await engine.dispatch(submitReq)
        XCTAssertEqual(submitRes.state.string("text"), "world")
    }

    // 3. Effect collection during dispatch
    func testEffectCollectionDuringDispatch() async throws {
        let script = """
        const handlers = {
            doCopy: (state, event, input) => {
                openclip.copy('copied: ' + input);
                return state;
            }
        };
        const ui = () => h('button', { title: 'Copy', handler: 'doCopy' });
        """
        let engine = JavaScriptCanvasEngine()
        let mountRes = try await engine.mount(CanvasMountRequest(input: "testText", scriptCode: script))

        let dispatchRes = try await engine.dispatch(CanvasDispatchRequest(
            event: CanvasEvent(kind: .tap, handler: "doCopy"),
            state: mountRes.state
        ))
        XCTAssertEqual(dispatchRes.effects, [CanvasEffect.copy("copied: testText")])
    }

    // 4. KeepVisible unwraps to inner leaf
    func testKeepVisibleUnwrapsToInnerLeaf() async throws {
        let script = """
        const handlers = {
            doKeep: (state) => {
                openclip.copy('xyz');
                openclip.keepVisible();
                return state;
            }
        };
        const ui = () => h('button', { title: 'Keep', handler: 'doKeep' });
        """
        let engine = JavaScriptCanvasEngine()
        let mountRes = try await engine.mount(CanvasMountRequest(input: "test", scriptCode: script))

        let dispatchRes = try await engine.dispatch(CanvasDispatchRequest(
            event: CanvasEvent(kind: .tap, handler: "doKeep"),
            state: mountRes.state
        ))
        XCTAssertEqual(dispatchRes.effects, [CanvasEffect.copy("xyz")])
    }

    // 5. Unknown handler re-renders with unchanged state
    func testUnknownHandlerRerendersWithUnchangedState() async throws {
        let script = """
        const initialState = { val: 'orig' };
        const ui = (state) => h('text', { content: 'Val: ' + state.val });
        """
        let engine = JavaScriptCanvasEngine()
        let mountRes = try await engine.mount(CanvasMountRequest(input: "test", scriptCode: script))

        let dispatchRes = try await engine.dispatch(CanvasDispatchRequest(
            event: CanvasEvent(kind: .tap, handler: "nonexistent"),
            state: mountRes.state
        ))

        XCTAssertEqual(dispatchRes.state.string("val"), "orig")
        guard case .text(let textProps) = dispatchRes.tree else {
            return XCTFail("Expected text root")
        }
        XCTAssertEqual(textProps.content, "Val: orig")
        XCTAssertTrue(dispatchRes.effects.isEmpty)
    }

    // 6. Mount tree limit rejected
    func testMountTreeLimitRejected() async throws {
        let script = """
        const ui = () => {
            let root = h('stack', { orientation: 'vertical' }, []);
            let current = root;
            for (let i = 0; i < 40; i++) {
                let next = h('stack', { orientation: 'vertical' }, []);
                current.children = [next];
                current = next;
            }
            return root;
        };
        """
        let engine = JavaScriptCanvasEngine()
        do {
            _ = try await engine.mount(CanvasMountRequest(input: "test", scriptCode: script))
            XCTFail("Expected mount to throw due to tree depth limit")
        } catch let error as CanvasJSRuntimeError {
            if case .scriptException = error {
                // Expected
            } else {
                XCTFail("Expected scriptException, got \(error)")
            }
        }
    }

    // 7. Non-object UI return rejected
    func testNonObjectUIReturnRejected() async throws {
        let script = "const ui = () => 42;"
        let engine = JavaScriptCanvasEngine()
        do {
            _ = try await engine.mount(CanvasMountRequest(input: "test", scriptCode: script))
            XCTFail("Expected mount to throw due to non-object UI return")
        } catch let error as CanvasJSRuntimeError {
            if case .scriptException = error {
                // Expected
            } else {
                XCTFail("Expected scriptException, got \(error)")
            }
        }
    }

    // 8. Missing UI declaration rejected
    func testMissingUIDeclarationRejected() async throws {
        let script = "const foo = 1;"
        let engine = JavaScriptCanvasEngine()
        do {
            _ = try await engine.mount(CanvasMountRequest(input: "test", scriptCode: script))
            XCTFail("Expected mount to throw due to missing UI symbol")
        } catch let error as CanvasJSRuntimeError {
            XCTAssertEqual(error, .missingUISymbol)
        }
    }

    // 9. Promise UI rejected on mount
    func testPromiseUIRejectedOnMount() async throws {
        let script = "const ui = () => new Promise(() => {});"
        let engine = JavaScriptCanvasEngine(timeout: 0.05)
        do {
            _ = try await engine.mount(CanvasMountRequest(input: "test", scriptCode: script))
            XCTFail("Expected mount to throw asyncNotSupported for promise returned by UI")
        } catch let error as CanvasJSRuntimeError {
            XCTAssertEqual(error, .asyncNotSupported)
        }
    }

    // 10. Sync cap respected
    func testSyncCapRespected() async throws {
        try await TestIsolation.GateSerializer.shared.serialize {
            let gate = OpenClipJSHost.syncEvaluationGate
            let maxSlots = OpenClipJSHost.syncEvaluationSlotCount
            var acquired = 0
            while acquired < maxSlots, gate.tryEnter() {
                acquired += 1
            }
            XCTAssertEqual(acquired, maxSlots, "Expected to drain every sync evaluation slot")
            defer {
                for _ in 0..<acquired {
                    gate.leave()
                }
            }

            let engine = JavaScriptCanvasEngine()
            let script = "const ui = () => h('text', { content: 'hi' });"
            do {
                _ = try await engine.mount(CanvasMountRequest(input: "test", scriptCode: script))
                XCTFail("Expected engine to refuse when sync evaluation gate is full")
            } catch let error as NSError {
                XCTAssertEqual(error.domain, Constants.actionErrorDomain)
                XCTAssertEqual(error.code, Int(Constants.actionErrorCode) + 2)
                XCTAssertTrue(error.localizedDescription.contains("Too many in-flight script evaluations"))
            }
        }
    }

    // 11. Watchdog sync loop still exits eventually
    func testWatchdogSyncLoopStillExitsEventually() async throws {
        let script = """
        const handlers = {
            loop: () => new Promise(() => {})
        };
        const ui = () => h('button', { title: 'Loop', handler: 'loop' });
        """
        let engine = JavaScriptCanvasEngine(timeout: 0.05)
        let mountRes = try await engine.mount(CanvasMountRequest(input: "test", scriptCode: script))

        do {
            _ = try await engine.dispatch(CanvasDispatchRequest(
                event: CanvasEvent(kind: .tap, handler: "loop"),
                state: mountRes.state
            ))
            XCTFail("Expected dispatch to exit and throw watchdog timeout")
        } catch let error as CanvasJSRuntimeError {
            if case .scriptException(let msg) = error {
                XCTAssertTrue(msg.contains("timed out"))
            } else {
                XCTFail("Expected scriptException, got \(error)")
            }
        }
    }

    // 12. Async UI rejected
    func testAsyncUIRejected() async throws {
        let script = "const ui = async () => h('text', { content: 'hi' });"
        let engine = JavaScriptCanvasEngine()
        do {
            _ = try await engine.mount(CanvasMountRequest(input: "test", scriptCode: script))
            XCTFail("Expected async ui to throw asyncNotSupported")
        } catch let error as CanvasJSRuntimeError {
            XCTAssertEqual(error, .asyncNotSupported)
        }
    }

    // 13. Gate slot release after watchdog fire
    func testGateSlotReleaseAfterWatchdogFire() async throws {
        let badScript = """
        const handlers = {
            loop: () => new Promise(() => {})
        };
        const ui = () => h('button', { title: 'Loop', handler: 'loop' });
        """
        let initialInFlight = OpenClipJSHost.syncEvaluationGate.inFlightCount
        let engine = JavaScriptCanvasEngine(timeout: 0.05)
        let mountRes = try await engine.mount(CanvasMountRequest(input: "test", scriptCode: badScript))

        do {
            _ = try await engine.dispatch(CanvasDispatchRequest(
                event: CanvasEvent(kind: .tap, handler: "loop"),
                state: mountRes.state
            ))
            XCTFail("Expected dispatch to throw watchdog timeout")
        } catch let error as CanvasJSRuntimeError {
            if case .scriptException(let msg) = error {
                XCTAssertTrue(msg.contains("timed out"))
            } else {
                XCTFail("Expected scriptException, got \(error)")
            }
        }

        XCTAssertEqual(OpenClipJSHost.syncEvaluationGate.inFlightCount, initialInFlight, "Gate slot must be released after watchdog timeout")

        let goodScript = "const ui = () => h('text', { content: 'good' });"
        let goodEngine = JavaScriptCanvasEngine()
        let mountRes2 = try await goodEngine.mount(CanvasMountRequest(input: "test", scriptCode: goodScript))
        guard case .text(let props) = mountRes2.tree else {
            return XCTFail("Expected text root")
        }
        XCTAssertEqual(props.content, "good")
    }

    // 14. Dispatch context reinstalls helpers
    func testDispatchContextReinstallsHelpers() async throws {
        let script = """
        const handlers = {
            checkHelpers: (state, event, input) => {
                if (typeof h !== 'function') throw new Error('h missing');
                if (typeof openclip !== 'object') throw new Error('openclip missing');
                if (openclip.options.unit !== 'celsius') throw new Error('options missing');
                return { ok: true };
            }
        };
        const ui = (state) => h('button', { title: 'Check', handler: 'checkHelpers' });
        """
        let engine = JavaScriptCanvasEngine()
        let mountReq = CanvasMountRequest(
            input: "test",
            optionValues: ["unit": .string("celsius")],
            scriptCode: script
        )
        let mountRes = try await engine.mount(mountReq)

        let dispatchRes = try await engine.dispatch(CanvasDispatchRequest(
            event: CanvasEvent(kind: .tap, handler: "checkHelpers"),
            state: mountRes.state
        ))
        XCTAssertEqual(dispatchRes.state.bool("ok"), true)
    }

    // 15. Async canvas settles promise
    func testAsyncCanvasSettlesPromise() async throws {
        let script = """
        const handlers = {
            asyncOp: (state) => new Promise((resolve) => {
                resolve({ asyncVal: 42 });
            })
        };
        const ui = (state) => h('text', { content: 'Val: ' + (state.asyncVal || 0) });
        """
        let engine = JavaScriptCanvasEngine()
        let mountRes = try await engine.mount(CanvasMountRequest(input: "test", scriptCode: script))

        let dispatchRes = try await engine.dispatch(CanvasDispatchRequest(
            event: CanvasEvent(kind: .tap, handler: "asyncOp"),
            state: mountRes.state
        ))

        XCTAssertEqual(dispatchRes.state["asyncVal"]?.numberValue, 42)
        guard case .text(let props) = dispatchRes.tree else {
            return XCTFail("Expected text root")
        }
        XCTAssertEqual(props.content, "Val: 42")
    }

    // 16. showContent(tree, {size}) captures preferredSize + overrides the mounted tree
    func testShowContentProvidesPreferredSize() async throws {
        let script = "const ui = () => { openclip.showContent(h('text', { content: 'x' }), { size: { width: 340, height: 220 } }); return h('text', { content: 'y' }); };"
        let engine = JavaScriptCanvasEngine()
        let mountRes = try await engine.mount(CanvasMountRequest(input: "test", scriptCode: script))

        XCTAssertEqual(mountRes.preferredSize, CanvasSize(width: 340, height: 220))
        guard case .text(let props) = mountRes.tree else {
            return XCTFail("Expected text root")
        }
        XCTAssertEqual(props.content, "x", "showContent'd tree must override the ui() return")
    }

    // 17. showContent without a size → preferredSize stays nil, tree still the showContent'd leaf
    func testShowContentWithoutSize() async throws {
        let script = "const ui = () => { openclip.showContent(h('text', { content: 'y' })); return h('text', { content: 'z' }); };"
        let engine = JavaScriptCanvasEngine()
        let mountRes = try await engine.mount(CanvasMountRequest(input: "test", scriptCode: script))

        XCTAssertNil(mountRes.preferredSize)
        guard case .text(let props) = mountRes.tree else {
            return XCTFail("Expected text root")
        }
        XCTAssertEqual(props.content, "y", "showContent'd tree must override the ui() return")
    }

    // 18. showStatus during dispatch surfaces on the dispatch result, state unchanged
    func testStatusDuringDispatchSurfaces() async throws {
        let script = """
        const handlers = {
            done: (state) => { openclip.showStatus('Done', 'info'); return state; }
        };
        const ui = () => h('button', { title: 'Go', handler: 'done' });
        """
        let engine = JavaScriptCanvasEngine()
        let mountRes = try await engine.mount(CanvasMountRequest(input: "test", scriptCode: script))

        let dispatchRes = try await engine.dispatch(CanvasDispatchRequest(
            event: CanvasEvent(kind: .tap, handler: "done"),
            state: mountRes.state
        ))
        XCTAssertEqual(dispatchRes.status, StatusFeedback(message: "Done", style: .info))
        XCTAssertEqual(dispatchRes.state, mountRes.state, "showStatus must not change state")
    }

    // 19. Rejected showContent payload fails the mount with a scriptException
    func testShowContentRejectedTreeThrows() async throws {
        let script = "const ui = () => { openclip.showContent('not-an-object'); return h('text', { content: 'ok' }); };"
        let engine = JavaScriptCanvasEngine()
        do {
            _ = try await engine.mount(CanvasMountRequest(input: "test", scriptCode: script))
            XCTFail("Expected mount to throw due to rejected showContent tree")
        } catch let error as CanvasJSRuntimeError {
            if case .scriptException = error {
                // Expected
            } else {
                XCTFail("Expected scriptException, got \(error)")
            }
        }
    }

    // 20. Mount-time side-effects thrown as scriptException
    func testMountTimeEffectsRejected() async throws {
        let script = "openclip.copy('illegal mount copy'); const ui = () => h('text', { content: 'ok' });"
        let engine = JavaScriptCanvasEngine()
        do {
            _ = try await engine.mount(CanvasMountRequest(input: "test", scriptCode: script))
            XCTFail("Expected mount to throw when side effects are requested at mount")
        } catch let error as CanvasJSRuntimeError {
            if case .scriptException(let msg) = error {
                XCTAssertTrue(msg.contains("Effects are not allowed at mount time"))
            } else {
                XCTFail("Expected scriptException, got \(error)")
            }
        }
    }
}
