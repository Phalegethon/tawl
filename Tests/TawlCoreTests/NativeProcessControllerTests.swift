import XCTest
import Foundation
@testable import TawlCore

final class NativeProcessControllerTests: XCTestCase {
    /// Creates and later removes only this test's own temporary executable.
    /// Signal tests never select an existing application or an unrelated PID.
    private func withFixture(_ body: (Process, RawProcess) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tawl-native-test-" + UUID().uuidString)
        let executable = directory.appendingPathComponent("Native Fixture.app/Contents/MacOS/fixture")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Native/process_control_fixture.c")
        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/clang")
        compiler.arguments = ["-Wall", "-Wextra", "-Werror", source.path, "-o", executable.path]
        try compiler.run()
        compiler.waitUntilExit()
        XCTAssertEqual(compiler.terminationStatus, 0)
        let child = Process()
        let input = Pipe(), output = Pipe()
        child.executableURL = executable
        child.arguments = ["normal"]
        child.standardInput = input
        child.standardOutput = output
        try child.run()
        defer {
            if child.isRunning { child.terminate() }
            child.waitUntilExit()
        }
        XCTAssertEqual(output.fileHandleForReading.readData(ofLength: 1), Data("R".utf8))
        let raw = try XCTUnwrap(NativeCollector().collect().processes.first { $0.pid == child.processIdentifier })
        try body(child, raw)
    }

    private func intent(_ raw: RawProcess, applicationName: String? = nil) throws -> ProcessClosureIntent {
        let identity = Attributor().identify(raw, among: [])
        var process = ProcessSample(id: raw.id, pid: raw.pid, name: raw.name,
                                    applicationID: identity.applicationID,
                                    applicationName: applicationName ?? identity.applicationName,
                                    cpuCores: 0, footprintBytes: 3_221_225_472)
        process.canReviewClosure = true
        var snapshot = Snapshot(monotonicTime: ProcessInfo.processInfo.systemUptime)
        snapshot.pressure = .warning
        snapshot.processes = [process]
        let assessment = assessProcess(process, snapshot: snapshot, history: [snapshot])
        return try prepareProcessClosure(process: process, snapshot: snapshot, assessment: assessment,
                                         now: snapshot.monotonicTime, isLive: true).get()
    }

    func testNativeAdapterRejectsDifferentAffectedApplicationAndClearedTickets() throws {
        try withFixture { child, raw in
            let controller = NativeProcessController()
            let wrong = try intent(raw, applicationName: "Different App")
            XCTAssertNotNil(controller.prepare(wrong))
            if case .sent = controller.submit(wrong) { XCTFail("Mismatched application must never receive a signal") }
            XCTAssertTrue(child.isRunning)
            let correct = try intent(raw)
            XCTAssertNil(controller.prepare(correct))
            controller.clear()
            if case .sent = controller.submit(correct) { XCTFail("Cleared confirmation must never receive a signal") }
            XCTAssertTrue(child.isRunning)
        }
    }

    func testNativeAdapterSignalsOnlyItsDisposableFixtureOnceAndObservesExit() throws {
        try withFixture { child, raw in
            let controller = NativeProcessController()
            let request = try intent(raw)
            XCTAssertNil(controller.prepare(request))
            guard case .alive = controller.observe(request) else { return XCTFail("Fixture must be observed alive") }
            guard case .sent = controller.submit(request) else { return XCTFail("Fixture signal should be accepted") }
            if case .sent = controller.submit(request) { XCTFail("A ticket cannot signal twice") }
            child.waitUntilExit()
            XCTAssertEqual(child.terminationReason, .uncaughtSignal)
            XCTAssertEqual(child.terminationStatus, 15)
            guard case .exited = controller.observe(request) else { return XCTFail("Fixture exit must be observed") }
        }
    }
}
