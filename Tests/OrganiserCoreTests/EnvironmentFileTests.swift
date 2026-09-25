import XCTest
@testable import OrganiserCore

final class EnvironmentFileTests: XCTestCase {
    func testSupportedDotenvForms() {
        for line in ["OPENROUTER_API_KEY=example", " export OPENROUTER_API_KEY = example # note", "OPENROUTER_API_KEY='example'", "OPENROUTER_API_KEY=\"example\" # note"] {
            XCTAssertEqual(EnvironmentFile.value("OPENROUTER_API_KEY", in: line), "example")
        }
    }
    func testIgnoresCommentsAndOtherKeys() {
        XCTAssertNil(EnvironmentFile.value("OPENROUTER_API_KEY", in: "# OPENROUTER_API_KEY=secret\nOTHER=example\nOPENROUTER_API_KEY="))
    }
    func testDoesNotEvaluateShellSyntax() {
        XCTAssertEqual(EnvironmentFile.value("KEY", in: "KEY='$(echo secret)'"), "$(echo secret)")
    }
    func testMalformedQuotesCannotBecomeKeys() {
        XCTAssertNil(EnvironmentFile.value("KEY", in: "KEY=\"unterminated"))
        XCTAssertNil(EnvironmentFile.value("KEY", in: "KEY='value' garbage"))
    }
    func testLastAssignmentWinsAndSupportsCRLF() {
        XCTAssertEqual(EnvironmentFile.value("KEY", in: "KEY=first\r\nKEY=second\r\n"), "second")
    }
}
