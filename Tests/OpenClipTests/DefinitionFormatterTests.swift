import XCTest
@testable import Core

final class DefinitionFormatterTests: XCTestCase {
    private let ambiguous = "ambiguous am·big·u·ous | amˈbiɡyəwəs | adjective (of language) open to more than one interpretation; having a double meaning: ambiguous phrases | the question is rather ambiguous. • unclear or inexact because a choice between alternatives has not been made: the result was ambiguous. DERIVATIVES ambiguousness | amˈbiɡyəwəsnəs | noun ORIGIN early 16th century (in the sense ‘indistinct, obscure’): from Latin ambiguus ‘doubtful’."

    func testSplitsHeaderPartOfSpeechSensesAndLabels() {
        let formatted = DefinitionFormatter.format(ambiguous)

        XCTAssertTrue(formatted.hasPrefix("ambiguous am·big·u·ous | amˈbiɡyəwəs\n\nadjective\n\n"), formatted)
        XCTAssertTrue(formatted.contains("\n\n• unclear or inexact"), formatted)
        XCTAssertTrue(formatted.contains("\n\nDERIVATIVES\nambiguousness"), formatted)
        XCTAssertTrue(formatted.contains("\n\nORIGIN\nearly 16th century"), formatted)
        XCTAssertFalse(formatted.contains(" • "), "subsense markers become list bullets")
    }

    func testSplitsNumberedSenses() {
        let raw = "run | rən | verb (runs) (, running | ˈrəniNG |) 1 [no object] move at a speed faster than a walk. 2 pass or cause to pass quickly. 3 extend or cause to extend in a particular direction. DERIVATIVES runnable | ˈrənəbəl | adjective ORIGIN Old English rinnan."
        let formatted = DefinitionFormatter.format(raw)

        XCTAssertTrue(formatted.contains("\n\n1. [no object] move"), formatted)
        XCTAssertTrue(formatted.contains("\n\n2. pass or cause to pass"), formatted)
        XCTAssertTrue(formatted.contains("\n\n3. extend or cause to extend"), formatted)
        XCTAssertTrue(formatted.contains("\n\nDERIVATIVES\nrunnable"), formatted)
        XCTAssertTrue(formatted.contains("\n\nORIGIN\nOld English"), formatted)
    }

    func testSplitsASecondPartOfSpeechAfterASense() {
        let raw = "thinking think·ing | ˈTHiNGkiNG | noun the process of using one's mind: they have done some thinking. • (thinkings) archaic thoughts; meditations: I am wrap'd in dismal thinkings. adjective [attributive] using thought or rational judgment; intelligent: he seemed to be a thinking man. PHRASES good thinking used as an expression of approval."
        let formatted = DefinitionFormatter.format(raw)

        XCTAssertTrue(formatted.contains("\n\nadjective\n\n[attributive] using thought"), formatted)
        XCTAssertFalse(formatted.contains("thinkings. adjective [attributive]"), formatted)
        XCTAssertTrue(formatted.contains("\n\nPHRASES\ngood thinking"), formatted)
    }

    func testRestartsSenseNumberingForEachPartOfSpeech() {
        let raw = "model mod·el | ˈmäd(ə)l | noun 1 a three-dimensional representation of a person or thing: a model airplane. • (in sculpture) a figure or object made in clay or wax: wax models were used in bronze casting. 2 a system or thing used as an example to follow: the law became a model. • (model of) a person or thing regarded as an excellent example: he was a model husband. verb (models) 1 fashion or shape (a three-dimensional figure or object) in a malleable material: use the icing to model a house. 2 (model something on/after) use (a system, procedure, etc.) as an example: the research method will be modeled on previous work."
        let formatted = DefinitionFormatter.format(raw)

        XCTAssertTrue(formatted.contains("\n\n1. a three-dimensional representation"), formatted)
        XCTAssertTrue(formatted.contains("\n\n2. a system or thing used"), formatted)
        XCTAssertTrue(formatted.contains("\n\n• (model of) a person"), formatted)
        XCTAssertTrue(formatted.contains("\n\nverb\n\n(models)"), formatted)
        XCTAssertTrue(formatted.contains("\n\n1. fashion or shape"), formatted)
        XCTAssertTrue(formatted.contains("\n\n2. (model something on/after)"), formatted)
    }

    func testLeavesUnrecognizedDefinitionsUnchanged() {
        let short = "a moment of sudden and great revelation or realization."
        XCTAssertEqual(DefinitionFormatter.format(short), short)
        XCTAssertEqual(DefinitionFormatter.format("  \(short) \n"), short)
    }

    func testLoneNumberInProseIsNotASenseMarker() {
        let raw = "sample | ˈsæmpəl | noun 1 percent of the total is enough."
        let formatted = DefinitionFormatter.format(raw)
        XCTAssertTrue(formatted.contains("noun\n\n1 percent"), formatted)
        XCTAssertFalse(formatted.contains("\n\n1. "), formatted)
    }
}
