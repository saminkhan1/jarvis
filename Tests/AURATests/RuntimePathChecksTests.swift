import XCTest
@testable import AURA

final class RuntimePathChecksTests: XCTestCase {
    func testMissingMCPCommandPathsFlagsAbsentResolvedCommands() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let scriptDir = tempRoot.appendingPathComponent("script", isDirectory: true)
        try FileManager.default.createDirectory(at: scriptDir, withIntermediateDirectories: true)

        let existing = scriptDir.appendingPathComponent("exists")
        FileManager.default.createFile(atPath: existing.path, contents: Data(), attributes: nil)

        let config = """
        mcp_servers:
          good:
            command: "${AURA_PROJECT_ROOT}/script/exists"
          missing:
            command: "${AURA_PROJECT_ROOT}/script/missing"
        """

        let missing = AURARuntimeChecks.missingMCPCommandPaths(in: config, projectRoot: tempRoot)
        XCTAssertEqual(missing, [tempRoot.appendingPathComponent("script/missing").path])
    }
}
