import Foundation
import XCTest
@testable import AURA

final class WrapperScriptTests: XCTestCase {
    func testAuraHermesWrapperDoesNotPatchHermesSQLiteState() throws {
        let scriptURL = AURAPaths.projectRoot.appendingPathComponent("script/aura-hermes")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        XCTAssertFalse(script.contains("sqlite3 \"$HERMES_HOME/state.db\""))
        XCTAssertFalse(script.contains("aura_quiet_close"))
    }
}
