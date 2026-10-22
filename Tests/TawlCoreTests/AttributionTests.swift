import XCTest
@testable import TawlCore

final class AttributionTests: XCTestCase {
    func testNestedHelperUsesOuterApplicationIdentity() {
        let p = RawProcess(pid: 1, startedAt: 1, name: "Code Helper", executablePath: "/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper.app/Contents/MacOS/helper")
        let value = Attributor().identify(p, among: [p])
        XCTAssertEqual(value.applicationName, "Visual Studio Code")
        XCTAssertFalse(value.applicationID.contains("/Applications"))
    }
    func testSameNamedWorkersBelongToSeparateProvenProjects() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["alpha", "beta"] {
            let dir = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: dir.appendingPathComponent("package.json"))
        }
        let a = RawProcess(pid: 1, startedAt: 1, name: "node", workingDirectory: root.appendingPathComponent("alpha").path)
        let b = RawProcess(pid: 2, startedAt: 2, name: "node", workingDirectory: root.appendingPathComponent("beta").path)
        let id = Attributor()
        let av = id.identify(a, among: [a,b]); let bv = id.identify(b, among: [a,b])
        XCTAssertEqual(av.projectName, "alpha"); XCTAssertEqual(bv.projectName, "beta")
        XCTAssertNotEqual(av.projectID, bv.projectID)
        XCTAssertFalse(av.projectID?.contains(root.path) ?? true)
        XCTAssertNil(id.identify(RawProcess(pid: 3, startedAt: 3, name: "node"), among: []).projectID)
    }
    func testGroupingCountsEachProcessOnceAndExposesMissingCPU() {
        var s = Snapshot()
        s.processes = [
            ProcessSample(id:"1:1",pid:1,name:"a",applicationID:"a",applicationName:"App",cpuCores:1,footprintBytes:100),
            ProcessSample(id:"2:2",pid:2,name:"b",applicationID:"a",applicationName:"App",cpuCores:nil,footprintBytes:200)
        ]
        let groups = groupProcesses(s, by: .application)
        XCTAssertEqual(groups.count,1)
        XCTAssertEqual(groups.first?.footprintBytes,300)
        XCTAssertEqual(groups.first?.unknownCPUCount,1)
        XCTAssertEqual(groups.first?.cpuCores,1)
    }
}
