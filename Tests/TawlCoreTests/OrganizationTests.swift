import XCTest
@testable import TawlCore

final class OrganizationTests: XCTestCase {
    private func process(_ id: String, app: String = "Unknown", name: String? = nil, cpu: Double? = nil, memory: UInt64? = nil, delta: Int64? = nil) -> ProcessSample {
        ProcessSample(id: id, pid: 100, name: name ?? app, applicationID: "app:" + app, applicationName: app,
                      cpuCores: cpu, footprintBytes: memory, memoryDeltaBytes: delta)
    }
    private func workload(_ id: String, name: String? = nil, cpu: Double? = nil, memory: UInt64? = nil, delta: Int64? = nil, count: Int = 1) -> Workload {
        Workload(id: id, name: name ?? id, memberIDs: (0..<count).map { "\(id)-\($0)" }, cpuCores: cpu,
                 footprintBytes: memory, memoryDeltaBytes: delta, unknownCPUCount: 0, unknownMemoryCount: 0)
    }
    func testMeasuredZeroPrecedesMissingInBothDirectionsForEveryNumericMetric() {
        let items = [workload("missing"), workload("zero", cpu: 0, memory: 0, delta: 0), workload("high", cpu: 3, memory: 300, delta: 300)]
        for key in [WorkloadSort.cpu, .footprint, .memoryDelta] {
            for direction in SortDirection.allCases {
                let sorted = sortedWorkloads(items, sort: key, direction: direction, snapshot: Snapshot())
                XCTAssertEqual(sorted.last?.id, "missing", "\(key), \(direction)")
                XCTAssertEqual(sorted.first?.id, direction == .ascending ? "zero" : "high")
            }
        }
    }
    func testSignedMemoryChangeAndEqualValuesHavePredictableOrdering() {
        let items = [workload("z", delta: -90), workload("a", delta: -90), workload("positive", delta: 30), workload("zero", delta: 0)]
        XCTAssertEqual(sortedWorkloads(items, sort: .memoryDelta, direction: .ascending, snapshot: Snapshot()).map(\.id), ["a", "z", "zero", "positive"])
        XCTAssertEqual(sortedWorkloads(items, sort: .memoryDelta, direction: .descending, snapshot: Snapshot()).map(\.id), ["positive", "zero", "a", "z"])
    }
    func testNameAndMemberSortingWorkInBothDirections() {
        let items = [workload("z", name: "Zed", count: 3), workload("c", name: "Chrome 10", count: 2), workload("a", name: "Chrome 2", count: 1)]
        XCTAssertEqual(sortedWorkloads(items, sort: .name, direction: .ascending, snapshot: Snapshot()).map(\.id), ["a", "c", "z"])
        XCTAssertEqual(sortedWorkloads(items, sort: .name, direction: .descending, snapshot: Snapshot()).map(\.id), ["z", "c", "a"])
        XCTAssertEqual(sortedWorkloads(items, sort: .members, direction: .ascending, snapshot: Snapshot()).map(\.id), ["a", "c", "z"])
        XCTAssertEqual(sortedWorkloads(items, sort: .members, direction: .descending, snapshot: Snapshot()).map(\.id), ["z", "c", "a"])
    }
    func testAutomaticFollowsPressureWhileManualSortStaysChosen() {
        let items = [workload("cpu", cpu: 5, memory: 10), workload("memory", cpu: 0, memory: 900)]
        var snapshot = Snapshot(); snapshot.pressure = .normal
        XCTAssertEqual(sortedWorkloads(items, sort: .automatic, direction: .descending, snapshot: snapshot).first?.id, "cpu")
        snapshot.pressure = .warning
        XCTAssertEqual(sortedWorkloads(items, sort: .automatic, direction: .descending, snapshot: snapshot).first?.id, "memory")
        XCTAssertEqual(sortedWorkloads(items, sort: .cpu, direction: .descending, snapshot: snapshot).first?.id, "cpu")
    }
    func testProcessRowsUseSignedDeltasAndTreatNonfiniteCPUAsMissing() {
        let items = [process("a", cpu: .nan, memory: nil, delta: nil), process("b", cpu: 0, memory: 0, delta: -20), process("c", cpu: 2, memory: 9, delta: 10)]
        XCTAssertEqual(sortedProcesses(items, sort: .cpu, direction: .ascending).map(\.id), ["b", "c", "a"])
        XCTAssertEqual(sortedProcesses(items, sort: .cpu, direction: .descending).map(\.id), ["c", "b", "a"])
        XCTAssertEqual(sortedProcesses(items, sort: .memoryDelta, direction: .ascending).map(\.id), ["b", "c", "a"])
        XCTAssertEqual(sortedProcesses(items, sort: .footprint, direction: .descending).map(\.id), ["c", "b", "a"])
        XCTAssertEqual(sortedProcesses(items, sort: .members, direction: .descending).map(\.id), ["a", "b", "c"])
    }
    func testKnownUsageFamiliesAndInheritedHelpersStayTogether() {
        let cases: [(String, String, UsageCategory)] = [
            ("Dia", "Browser Helper (Renderer)", .browsers),
            ("Google Chrome", "Google Chrome Helper", .browsers),
            ("Claude", "node", .ai), ("Visual Studio Code", "node", .development),
            ("Slack", "Slack Helper", .communication), ("Docker", "com.docker.backend", .virtualization),
            ("postgres", "postgres", .databases), ("Spotify", "Spotify Helper", .media),
            ("WindowServer", "WindowServer", .system)
        ]
        for (app, name, expected) in cases { XCTAssertEqual(usageCategory(for: process("p", app: app, name: name)), expected, app) }
        XCTAssertEqual(usageCategory(for: process("p", app: "com.apple.Virtualization.VirtualMachine")), .virtualization)
        XCTAssertEqual(usageCategory(for: process("p", app: "python3.12")), .development)
    }
    func testAmbiguousAndLookalikeNamesRemainOther() {
        for name in ["Browser Helper (Renderer)", "chromedriver-not-browser", "my-node-exporter", "ClaudeBook", "com.apple.unknown", "python3.custom", "python3."] {
            XCTAssertEqual(usageCategory(for: process("p", app: name)), .other, name)
        }
        XCTAssertEqual(usageCategory(for: process("p", app: "Unknown App", name: "node")), .other)
    }
    func testCategoryGroupingDeduplicatesWithoutChangingAppOrProjectMembership() {
        var safari = process("s", app: "Safari", cpu: 0.5, memory: 100)
        safari.projectID = "project:demo"; safari.projectName = "Demo"
        let chrome = process("c", app: "Google Chrome", cpu: 1.5, memory: 300)
        let other = process("o", app: "Unknown", cpu: nil, memory: nil)
        var snapshot = Snapshot(); snapshot.processes = [safari, chrome, safari, other]
        let categories = groupProcesses(snapshot, by: .category)
        XCTAssertEqual(categories.count, 2)
        let browser = categories.first { $0.id == "category:browsers" }
        XCTAssertEqual(browser?.name, "Tarayıcılar")
        XCTAssertEqual(browser?.memberIDs, ["c", "s"])
        XCTAssertEqual(browser?.cpuCores, 2)
        XCTAssertEqual(browser?.footprintBytes, 400)
        XCTAssertEqual(groupProcesses(snapshot, by: .application).count, 3)
        XCTAssertEqual(groupProcesses(snapshot, by: .project).first { $0.id == "project:demo" }?.memberIDs, ["s"])
        XCTAssertEqual(workloadGroupIdentity(for: chrome, by: .category).id, browser?.id)
    }
}
