import XCTest
@testable import Core
@testable import OpenClip

final class DefaultActionFactoryTests: XCTestCase {
    func testFactoryRoutesJavaScriptFileToJavaScriptAction() async {
        let factory = DefaultActionFactory()
        let actionMeta = ExtensionActionMetadata(title: "JS Action", icon: "symbol:code", script: "test.js", url: nil, regex: nil)
        let manifest = ExtensionMetadata(identifier: "com.test.js", name: "JS Test", actions: [actionMeta], options: nil)
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let jsFile = tempDir.appendingPathComponent("test.js")
        try? "console.log('hello');".write(to: jsFile, atomically: true, encoding: .utf8)
        
        let action = await factory.createAction(metadata: actionMeta, manifest: manifest, directoryURL: tempDir, index: 0)
        XCTAssertTrue(action is JavaScriptAction)
        
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    func testFactoryRoutesAppleScriptFileToAppleScriptAction() async {
        let factory = DefaultActionFactory()
        let actionMeta = ExtensionActionMetadata(title: "AppleScript Action", icon: "symbol:applescript", script: "test.applescript", url: nil, regex: nil)
        let manifest = ExtensionMetadata(identifier: "com.test.applescript", name: "AppleScript Test", actions: [actionMeta], options: nil)
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let scriptFile = tempDir.appendingPathComponent("test.applescript")
        try? "return \"hello\"".write(to: scriptFile, atomically: true, encoding: .utf8)
        
        let action = await factory.createAction(metadata: actionMeta, manifest: manifest, directoryURL: tempDir, index: 0)
        XCTAssertTrue(action is AppleScriptAction)
        
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    func testFactoryRoutesURLTemplateToURLTemplateAction() async {
        let factory = DefaultActionFactory()
        let actionMeta = ExtensionActionMetadata(title: "URL Action", icon: "symbol:link", script: nil, url: "https://example.com/{query}", regex: ".*")
        let manifest = ExtensionMetadata(identifier: "com.test.url", name: "URL Test", actions: [actionMeta], options: nil)
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let action = await factory.createAction(metadata: actionMeta, manifest: manifest, directoryURL: tempDir, index: 0)
        XCTAssertTrue(action is URLTemplateAction)
        
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    func testFactoryRoutesDefaultScriptToScriptAction() async {
        let factory = DefaultActionFactory()
        let actionMeta = ExtensionActionMetadata(title: "Shell Action", icon: "symbol:terminal", script: "test.sh", url: nil, regex: nil)
        let manifest = ExtensionMetadata(identifier: "com.test.sh", name: "Shell Test", actions: [actionMeta], options: nil)
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let scriptFile = tempDir.appendingPathComponent("test.sh")
        try? "#!/bin/sh\necho hi".write(to: scriptFile, atomically: true, encoding: .utf8)
        
        let action = await factory.createAction(metadata: actionMeta, manifest: manifest, directoryURL: tempDir, index: 0)
        XCTAssertTrue(action is ScriptAction)
        
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testFactoryRejectsScriptPathTraversalEscapingDirectory() async {
        let factory = DefaultActionFactory()
        let actionMeta = ExtensionActionMetadata(title: "Malicious Shell", icon: "symbol:terminal", script: "../secret.sh", url: nil, regex: nil)
        let manifest = ExtensionMetadata(identifier: "com.test.traversal", name: "Traversal Test", actions: [actionMeta], options: nil)
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let parentDir = tempDir.appendingPathComponent("parent")
        let extDir = parentDir.appendingPathComponent("myext")
        try? FileManager.default.createDirectory(at: extDir, withIntermediateDirectories: true)
        let secretFile = parentDir.appendingPathComponent("secret.sh")
        try? "#!/bin/sh\necho secret".write(to: secretFile, atomically: true, encoding: .utf8)
        
        let action = await factory.createAction(metadata: actionMeta, manifest: manifest, directoryURL: extDir, index: 0)
        XCTAssertNil(action, "Script path traversal outside extension directory must be rejected by factory")
        
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testFactoryRejectsAbsoluteScriptPath() async {
        let factory = DefaultActionFactory()
        let actionMeta = ExtensionActionMetadata(title: "Absolute Shell", icon: "symbol:terminal", script: "/bin/zsh", url: nil, regex: nil)
        let manifest = ExtensionMetadata(identifier: "com.test.absolute", name: "Absolute Test", actions: [actionMeta], options: nil)
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let action = await factory.createAction(metadata: actionMeta, manifest: manifest, directoryURL: tempDir, index: 0)
        XCTAssertNil(action, "Absolute script path must be rejected by factory")
        
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testFactoryRejectsSymlinkEscapingDirectory() async {
        let factory = DefaultActionFactory()
        let actionMeta = ExtensionActionMetadata(title: "Symlink Shell", icon: "symbol:terminal", script: "evil.sh", url: nil, regex: nil)
        let manifest = ExtensionMetadata(identifier: "com.test.symlink", name: "Symlink Test", actions: [actionMeta], options: nil)
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let symlinkURL = tempDir.appendingPathComponent("evil.sh")
        try? FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: URL(fileURLWithPath: "/bin/zsh"))
        
        let action = await factory.createAction(metadata: actionMeta, manifest: manifest, directoryURL: tempDir, index: 0)
        XCTAssertNil(action, "Symlink pointing outside package directory must be rejected by factory")
        
        try? FileManager.default.removeItem(at: tempDir)
    }

    @MainActor
    func testFactoryMapsLoadingFlagOntoChrome() async {
        let factory = DefaultActionFactory()
        let loadingMeta = ExtensionActionMetadata(title: "Loading", icon: "symbol:play", script: "test.applescript", type: "applescript", loading: true, loadingMessage: "Connecting to Music…")
        let plainMeta = ExtensionActionMetadata(title: "Plain", icon: "symbol:play", script: "test2.applescript", type: "applescript")
        let manifest = ExtensionMetadata(identifier: "com.test.loading", name: "Loading Test", actions: [loadingMeta, plainMeta], options: nil)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try? "return \"hi\"".write(to: tempDir.appendingPathComponent("test.applescript"), atomically: true, encoding: .utf8)
        try? "return \"hi\"".write(to: tempDir.appendingPathComponent("test2.applescript"), atomically: true, encoding: .utf8)

        guard let loading = await factory.createAction(metadata: loadingMeta, manifest: manifest, directoryURL: tempDir, index: 0) as? AppleScriptAction else {
            try? FileManager.default.removeItem(at: tempDir)
            return XCTFail("Expected AppleScriptAction")
        }
        XCTAssertTrue(loading.chrome.showsLoading)
        XCTAssertEqual(loading.chrome.loadingMessage, "Connecting to Music…")

        guard let plain = await factory.createAction(metadata: plainMeta, manifest: manifest, directoryURL: tempDir, index: 1) as? AppleScriptAction else {
            try? FileManager.default.removeItem(at: tempDir)
            return XCTFail("Expected AppleScriptAction")
        }
        XCTAssertFalse(plain.chrome.showsLoading)
        XCTAssertNil(plain.chrome.loadingMessage)

        try? FileManager.default.removeItem(at: tempDir)
    }

    func testUniformIDBareSlugExpandsWithManifestIdentifier() async {
        let factory = DefaultActionFactory()
        let actionMeta = ExtensionActionMetadata(id: "a", title: "Action A", icon: "symbol:link", script: nil, url: "https://example.com/a?q={query}", regex: nil)
        let manifest = ExtensionMetadata(identifier: "pkg", name: "Pkg", actions: [actionMeta], options: nil)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let action = await factory.createAction(metadata: actionMeta, manifest: manifest, directoryURL: tempDir, index: 0)
        XCTAssertEqual(action?.id, "pkg.a")

        try? FileManager.default.removeItem(at: tempDir)
    }

    func testUniformIDFullIDUsedVerbatim() async {
        let factory = DefaultActionFactory()
        let actionMeta = ExtensionActionMetadata(id: "com.custom.namespaced.action", title: "Action", icon: "symbol:link", script: nil, url: "https://example.com?q={query}", regex: nil)
        let manifest = ExtensionMetadata(identifier: "pkg", name: "Pkg", actions: [actionMeta], options: nil)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let action = await factory.createAction(metadata: actionMeta, manifest: manifest, directoryURL: tempDir, index: 0)
        XCTAssertEqual(action?.id, "com.custom.namespaced.action")

        try? FileManager.default.removeItem(at: tempDir)
    }

    func testUniformIDIndexFallbackIgnoresTitle() async {
        let factory = DefaultActionFactory()
        let actionMeta = ExtensionActionMetadata(title: "Some Title", icon: "symbol:link", script: nil, url: "https://example.com?q={query}", regex: nil)
        let manifest = ExtensionMetadata(identifier: "pkg", name: "Pkg", actions: [actionMeta], options: nil)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let action = await factory.createAction(metadata: actionMeta, manifest: manifest, directoryURL: tempDir, index: 2)
        XCTAssertEqual(action?.id, "pkg.action.2")

        try? FileManager.default.removeItem(at: tempDir)
    }

    func testGroupActionIsNotRunnableAsSingleButFlattensViaCreateActions() async {
        let factory = DefaultActionFactory()
        let actionMeta = ExtensionActionMetadata(
            id: "tools",
            title: "Group",
            type: "group",
            subActions: [
                ExtensionActionMetadata(id: "sub", title: "Sub Action", url: "https://example.com?q={query}", type: "url")
            ]
        )
        let manifest = ExtensionMetadata(identifier: "pkg", name: "Pkg", actions: [actionMeta], options: nil)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // The single-action seam keeps groups schema-only (never a runnable bare group row).
        let action = await factory.createAction(metadata: actionMeta, manifest: manifest, directoryURL: tempDir, index: 0)
        XCTAssertNil(action)

        // The registry path flattens: a GroupAction row plus sub-actions under the ID-prefix convention.
        let flattened = await factory.createActions(metadata: actionMeta, manifest: manifest, directoryURL: tempDir, index: 0)
        XCTAssertEqual(flattened.count, 2)
        XCTAssertTrue(flattened[0] is GroupAction)
        XCTAssertEqual(flattened[0].id, "pkg.tools")
        XCTAssertEqual(flattened[1].id, "pkg.tools.sub")

        try? FileManager.default.removeItem(at: tempDir)
    }

    func testFactoryDecoratesActionsThatDeclareMenuBehavior() async {
        let factory = DefaultActionFactory()
        let declaring = ExtensionActionMetadata(
            id: "slug",
            title: "Slugify",
            url: "https://example.com/slug?q={query}",
            type: "url",
            menuRelevance: "\\s"
        )
        let plain = ExtensionActionMetadata(
            id: "open",
            title: "Open",
            url: "https://example.com?q={query}",
            type: "url"
        )
        let manifest = ExtensionMetadata(identifier: "pkg", name: "Pkg", actions: [declaring, plain], options: nil)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        guard let decorated = await factory.createAction(metadata: declaring, manifest: manifest, directoryURL: tempDir, index: 0) as? MenuDecoratedAction else {
            return XCTFail("Declaring action should be wrapped in MenuDecoratedAction")
        }
        XCTAssertEqual(decorated.id, "pkg.slug")
        XCTAssertTrue(decorated.base is URLTemplateAction)
        XCTAssertEqual(decorated.menuRelevanceRegex, "\\s")
        XCTAssertTrue(decorated.isRelevant(for: "a b"))
        XCTAssertFalse(decorated.isRelevant(for: "ab"))

        let plainAction = await factory.createAction(metadata: plain, manifest: manifest, directoryURL: tempDir, index: 1)
        XCTAssertTrue(plainAction is URLTemplateAction)
        XCTAssertFalse(plainAction is MenuDecoratedAction)

        try? FileManager.default.removeItem(at: tempDir)
    }

    func testFactoryLeavesSubActionsWithoutMenuBehaviorPlain() async {
        let factory = DefaultActionFactory()
        let groupMeta = ExtensionActionMetadata(
            id: "tools",
            title: "Group",
            type: "group",
            subActions: [
                ExtensionActionMetadata(id: "upper", title: "Uppercase", url: "https://example.com?q={query}", type: "url")
            ]
        )
        let manifest = ExtensionMetadata(identifier: "pkg", name: "Pkg", actions: [groupMeta], options: nil)
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let flattened = await factory.createActions(metadata: groupMeta, manifest: manifest, directoryURL: tempDir, index: 0)
        XCTAssertEqual(flattened.count, 2)
        XCTAssertTrue(flattened[0] is GroupAction)
        XCTAssertEqual(flattened[1].id, "pkg.tools.upper")
        XCTAssertFalse(flattened[1] is MenuDecoratedAction, "sub-actions without menuRelevance stay plain")

        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Rules attachment (Phase 4 visibility)

    @MainActor
    func testFactoryAttachesRulesToURLAction() async {
        let factory = DefaultActionFactory()
        let actionMeta = ExtensionActionMetadata(
            title: "URL Action",
            icon: "symbol:link",
            url: "https://example.com/?q={text}",
            regex: "^[a-z]+$",
            requirements: ActionRequirements(apps: ["com.allowed"], appsMode: .allow)
        )
        let manifest = ExtensionMetadata(identifier: "com.test.rules", name: "Rules Test", actions: [actionMeta], options: nil)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        guard let action = await factory.createAction(metadata: actionMeta, manifest: manifest, directoryURL: tempDir, index: 0) as? URLTemplateAction else {
            XCTFail("Expected URLTemplateAction")
            try? FileManager.default.removeItem(at: tempDir)
            return
        }
        XCTAssertEqual(action.rules?.legacyRegex, "^[a-z]+$")
        XCTAssertEqual(action.rules?.requirements?.apps, ["com.allowed"])

        // Allow-list filtering flows through ActionVisibility.
        let allowedContext = ActionContext(
            selection: SelectionContext(text: "hello", sourceApp: AppIdentity(bundleIdentifier: "com.allowed", localizedName: "Allowed"), cursorPosition: .zero, timestamp: Date(), appPolicy: .default),
            modifiers: []
        )
        let deniedContext = ActionContext(
            selection: SelectionContext(text: "hello", sourceApp: AppIdentity(bundleIdentifier: "com.other", localizedName: "Other"), cursorPosition: .zero, timestamp: Date(), appPolicy: .default),
            modifiers: []
        )
        XCTAssertTrue(action.isEnabled(for: allowedContext))
        XCTAssertFalse(action.isEnabled(for: deniedContext))

        try? FileManager.default.removeItem(at: tempDir)
    }

    @MainActor
    func testFactoryAttachesRulesToScriptFileAction() async {
        let factory = DefaultActionFactory()
        let actionMeta = ExtensionActionMetadata(
            title: "Shell Action",
            icon: "symbol:terminal",
            script: "test.sh",
            requirements: ActionRequirements(regex: "^[0-9]+$")
        )
        let manifest = ExtensionMetadata(identifier: "com.test.shell", name: "Shell Test", actions: [actionMeta], options: nil)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let scriptFile = tempDir.appendingPathComponent("test.sh")
        try? "#!/bin/sh\necho hi".write(to: scriptFile, atomically: true, encoding: .utf8)

        guard let action = await factory.createAction(metadata: actionMeta, manifest: manifest, directoryURL: tempDir, index: 0) as? ScriptAction else {
            XCTFail("Expected ScriptAction")
            try? FileManager.default.removeItem(at: tempDir)
            return
        }
        XCTAssertEqual(action.rules?.requirements?.regex, "^[0-9]+$")

        let context = ActionContext(
            selection: SelectionContext(text: "123", sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"), cursorPosition: .zero, timestamp: Date(), appPolicy: .default),
            modifiers: []
        )
        XCTAssertTrue(action.isEnabled(for: context))

        try? FileManager.default.removeItem(at: tempDir)
    }

    @MainActor
    func testFactoryAttachesRulesToShellInlineCustomAction() async {
        let factory = DefaultActionFactory()
        let actionMeta = ExtensionActionMetadata(
            title: "Shell Inline",
            icon: "symbol:terminal",
            type: "shell",
            scriptCode: "echo hi",
            requirements: ActionRequirements(apps: ["com.allowed"], appsMode: .deny)
        )
        let manifest = ExtensionMetadata(identifier: "com.test.shellinline", name: "Shell Inline Test", actions: [actionMeta], options: nil)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        guard let action = await factory.createAction(metadata: actionMeta, manifest: manifest, directoryURL: tempDir, index: 0) as? CustomAction else {
            XCTFail("Expected CustomAction")
            try? FileManager.default.removeItem(at: tempDir)
            return
        }
        XCTAssertNotNil(action.rules)
        XCTAssertEqual(action.rules?.requirements?.appsMode, .deny)

        // Deny-list filtering flows through ActionVisibility on the shellInline path too.
        let deniedContext = ActionContext(
            selection: SelectionContext(text: "hello", sourceApp: AppIdentity(bundleIdentifier: "com.allowed", localizedName: "Allowed"), cursorPosition: .zero, timestamp: Date(), appPolicy: .default),
            modifiers: []
        )
        let allowedContext = ActionContext(
            selection: SelectionContext(text: "hello", sourceApp: AppIdentity(bundleIdentifier: "com.other", localizedName: "Other"), cursorPosition: .zero, timestamp: Date(), appPolicy: .default),
            modifiers: []
        )
        XCTAssertFalse(action.isEnabled(for: deniedContext))
        XCTAssertTrue(action.isEnabled(for: allowedContext))

        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Delivery declaration (manifest secondary/toast onto Action.delivery)

    func testFactoryMapsManifestDeliveryOntoActionDelivery() async {
        let factory = DefaultActionFactory()
        let declaring = ExtensionActionMetadata(
            id: "sec",
            title: "Alt",
            url: "https://example.com?q={query}",
            type: "url",
            secondary: ExtensionSecondaryDeclaration(type: "copy", value: "alternate", message: nil),
            toast: ExtensionToastDeclaration(message: "Copied", style: "success"),
            secondaryToast: ExtensionToastDeclaration(message: "Alt copied", style: "info")
        )
        let plain = ExtensionActionMetadata(
            id: "open",
            title: "Open",
            url: "https://example.com?q={query}",
            type: "url"
        )
        let manifest = ExtensionMetadata(identifier: "pkg", name: "Pkg", actions: [declaring, plain], options: nil)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        guard let action = await factory.createAction(metadata: declaring, manifest: manifest, directoryURL: tempDir, index: 0) as? DeliveryDecoratedAction else {
            try? FileManager.default.removeItem(at: tempDir)
            return XCTFail("Declaring action should be wrapped in DeliveryDecoratedAction")
        }
        XCTAssertEqual(action.id, "pkg.sec")
        XCTAssertTrue(action.base is URLTemplateAction)
        guard case .copy(let value)? = action.delivery?.secondary else {
            try? FileManager.default.removeItem(at: tempDir)
            return XCTFail("secondary should map to .copy")
        }
        XCTAssertEqual(value, "alternate")
        XCTAssertEqual(action.delivery?.primaryToast, StatusFeedback(message: "Copied", style: .success))
        XCTAssertEqual(action.delivery?.secondaryToast, StatusFeedback(message: "Alt copied", style: .info))

        let plainAction = await factory.createAction(metadata: plain, manifest: manifest, directoryURL: tempDir, index: 1)
        XCTAssertNil(plainAction?.delivery)
        XCTAssertFalse(plainAction is DeliveryDecoratedAction)

        try? FileManager.default.removeItem(at: tempDir)
    }

    func testFactoryMapsManifestToastSecondaryOntoToastDelivery() async {
        let factory = DefaultActionFactory()
        let declaring = ExtensionActionMetadata(
            id: "toast",
            title: "Heads Up",
            url: "https://example.com?q={query}",
            type: "url",
            secondary: ExtensionSecondaryDeclaration(type: "toast", value: nil, message: "Heads up")
        )
        let manifest = ExtensionMetadata(identifier: "pkg", name: "Pkg", actions: [declaring], options: nil)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        guard let action = await factory.createAction(metadata: declaring, manifest: manifest, directoryURL: tempDir, index: 0) as? DeliveryDecoratedAction else {
            try? FileManager.default.removeItem(at: tempDir)
            return XCTFail("Declaring action should be wrapped in DeliveryDecoratedAction")
        }
        guard case .toast(let feedback)? = action.delivery?.secondary else {
            try? FileManager.default.removeItem(at: tempDir)
            return XCTFail("secondary should map to .toast")
        }
        XCTAssertEqual(feedback, StatusFeedback(message: "Heads up", style: .info))

        try? FileManager.default.removeItem(at: tempDir)
    }

    func testFactoryComposesMenuAndDeliveryDecoration() async {
        let factory = DefaultActionFactory()
        let combo = ExtensionActionMetadata(
            id: "combo",
            title: "Combo",
            url: "https://example.com?q={query}",
            type: "url",
            menuRelevance: "\\s",
            secondary: ExtensionSecondaryDeclaration(type: "paste", value: "alt", message: nil)
        )
        let manifest = ExtensionMetadata(identifier: "pkg", name: "Pkg", actions: [combo], options: nil)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        guard let menu = await factory.createAction(metadata: combo, manifest: manifest, directoryURL: tempDir, index: 0) as? MenuDecoratedAction else {
            try? FileManager.default.removeItem(at: tempDir)
            return XCTFail("Both declarations should keep menuRelevance decoration outermost")
        }
        guard let delivery = menu.base as? DeliveryDecoratedAction else {
            try? FileManager.default.removeItem(at: tempDir)
            return XCTFail("menuRelevance outer wrapper should carry the DeliveryDecoratedAction inside")
        }
        guard case .paste(let value)? = delivery.delivery?.secondary else {
            try? FileManager.default.removeItem(at: tempDir)
            return XCTFail("secondary should map to .paste")
        }
        XCTAssertEqual(value, "alt")
        // The declared delivery must stay reachable on the outermost wrapper the registry holds.
        guard case .paste(let outerValue)? = menu.delivery?.secondary else {
            try? FileManager.default.removeItem(at: tempDir)
            return XCTFail("MenuDecoratedAction should forward delivery to its base")
        }
        XCTAssertEqual(outerValue, "alt")

        try? FileManager.default.removeItem(at: tempDir)
    }
}
