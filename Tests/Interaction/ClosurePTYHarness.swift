import Foundation
@testable import TawlCore

// Runs the real terminal input loop with synthetic snapshots and a log-only
// controller. No NativeProcessController is constructed; no PID is signalled.
final class ClosureSpy: ProcessClosureControlling {
    let log: FileHandle
    let controlPath: String
    private var prepared: (id: String, time: Double)?
    init(path: String, controlPath: String) throws {
        self.controlPath=controlPath
        FileManager.default.createFile(atPath:path, contents:Data())
        log = try FileHandle(forWritingTo:URL(fileURLWithPath:path))
    }
    var mode: String {
        ((try? String(contentsOfFile:controlPath,encoding:.utf8)) ?? "normal").trimmingCharacters(in:.whitespacesAndNewlines)
    }
    private func append(_ entry: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject:entry,options:[.sortedKeys]) {
            log.write(data);log.write(Data([10]))
        }
    }
    func write(_ event: String, _ intent: ProcessClosureIntent? = nil) {
        var entry: [String: Any] = ["event":event,"time":ProcessInfo.processInfo.systemUptime]
        if let intent {
            entry["processID"] = intent.processID
            entry["pid"] = Int(intent.pid)
            entry["applicationID"] = intent.applicationID
        }
        append(entry)
    }
    func sample(_ snapshot: Snapshot) {
        append(["event":"sample","time":snapshot.monotonicTime,
                "cpu":snapshot.cpuPercent.map { $0 as Any } ?? NSNull(),
                "mode":mode])
    }
    private func matches(_ intent: ProcessClosureIntent) -> Bool {
        prepared?.id == intent.processID && prepared?.time == intent.createdAt
    }
    func prepare(_ intent: ProcessClosureIntent) -> String? {
        write("prepare",intent)
        if mode == "prepare-failure" { prepared=nil; return "Synthetic native preparation failed." }
        prepared=(intent.processID,intent.createdAt); return nil
    }
    func submit(_ intent: ProcessClosureIntent) -> ProcessClosureSubmission {
        write("submit",intent)
        guard matches(intent) else { write("rejected",intent);return .rejected("Synthetic preparation is no longer bound to this target.") }
        if mode == "reject" {write("rejected",intent);return .rejected("The synthetic controller rejected the request.")}
        write("sent",intent);return .sent
    }
    func observe(_ intent: ProcessClosureIntent) -> ProcessClosureObservation {
        write("observe",intent)
        guard matches(intent) else {return .unreadable}
        return mode == "exited" ? .exited:.alive
    }
    func clear() { prepared=nil;write("clear") }
}

L10n.configure(AppLanguage(rawValue: ProcessInfo.processInfo.environment["TAWL_LANG"] ?? "en") ?? .english)

let args = CommandLine.arguments
guard args.count == 3 else { fatalError("log path and scenario control path required") }
let spy = try ClosureSpy(path:args[1],controlPath:args[2])
var lastTime: Double?
try TerminalUI(processController:spy).run(nextSnapshot: {
    let mode = spy.mode
    let now = ProcessInfo.processInfo.systemUptime
    var snapshot = Snapshot(timestamp:Date(),monotonicTime:mode == "stale" ? now-10:now)
    snapshot.intervalSeconds = lastTime.map { now-$0 };lastTime=now
    snapshot.logicalCPUCount=8;snapshot.cpuPercent=12
    snapshot.pressure = mode == "withdrawn" ? .normal:.warning
    snapshot.memoryTotalBytes=34_359_738_368
    snapshot.swapUsedBytes=12_884_901_888;snapshot.swapOutBytesPerSecond=4_194_304;snapshot.swapInBytesPerSecond=1_048_576
    if mode == "improved" {
        snapshot.cpuPercent=4;snapshot.pressure = .normal
        snapshot.swapUsedBytes=10_737_418_240;snapshot.swapOutBytesPerSecond=0
    } else if mode == "worse" {
        snapshot.cpuPercent=92;snapshot.pressure = .critical
        snapshot.swapUsedBytes=15_032_385_536;snapshot.swapOutBytesPerSecond=12_582_912
    } else if mode == "missing" {
        snapshot.cpuPercent=nil;snapshot.pressure = .unknown
        snapshot.swapUsedBytes=nil;snapshot.swapOutBytesPerSecond=nil;snapshot.swapInBytesPerSecond=nil
    }
    var original = ProcessSample(id:mode == "replaced" ? "42:101":"42:100",pid:42,name:"Fixture Worker A",
                                 applicationID:"app:fixture",applicationName:"Fixture Editor",
                                 cpuCores:0.1,footprintBytes:3_221_225_472)
    original.canReviewClosure=true;original.ageSeconds=3600
    var sibling=ProcessSample(id:"43:100",pid:43,name:"Fixture Worker B",applicationID:"app:fixture",
                              applicationName:"Fixture Editor",cpuCores:0.1,
                              footprintBytes:mode == "resort" ? 8_589_934_592:2_684_354_560)
    sibling.canReviewClosure=true;sibling.ageSeconds=3600
    snapshot.processes=[original,sibling]
    if mode == "outside-group" {
        snapshot.processes[0].footprintBytes=104_857_600
        snapshot.processes[1].footprintBytes=104_857_600
        var outside=ProcessSample(id:"44:100",pid:44,name:"Outside Worker",applicationID:"app:outside",
                                  applicationName:"Zulu Editor",cpuCores:0.1,footprintBytes:3_221_225_472)
        outside.canReviewClosure=true;outside.ageSeconds=3600
        snapshot.processes.append(outside)
    }
    if mode == "unowned" { snapshot.processes[0].canReviewClosure=false }
    if mode == "changed-app" { snapshot.processes[0].applicationID="app:changed";snapshot.processes[0].applicationName="Changed App" }
    snapshot.totalProcessCount=snapshot.processes.count
    if mode == "long" {
        for i in snapshot.processes.indices {
            snapshot.processes[i].name = String(repeating:"Fixture Worker ",count:50)
            snapshot.processes[i].applicationName = String(repeating:"Fixture Editor ",count:50)
        }
    }
    spy.sample(snapshot)
    return snapshot
},interval:0.2)
