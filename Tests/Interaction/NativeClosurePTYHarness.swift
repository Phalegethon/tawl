import Foundation
@testable import TawlCore

// Real collector, real reducer, real terminal loop, real native controller.
// The wrapper can prepare/signal only the disposable child created below.
final class FixtureOnlyController: ProcessClosureControlling {
    let pid:Int32
    let native=NativeProcessController()
    let log:FileHandle
    init(pid:Int32,log:FileHandle){self.pid=pid;self.log=log}
    func record(_ event:String,_ fields:[String:Any]=[:]) {
        var record=fields;record["event"]=event
        record["time"]=ProcessInfo.processInfo.systemUptime
        let data=try! JSONSerialization.data(withJSONObject:record,options:[.sortedKeys])
        log.write(data);log.write(Data([10]))
    }
    func prepare(_ intent:ProcessClosureIntent)->String? {
        guard intent.pid==pid else{return "The test can select only its own disposable process."}
        let error=native.prepare(intent)
        record("prepare",["pid":Int(intent.pid),"processID":intent.processID,
                          "app":intent.applicationName,"reasons":intent.reasons,"error":error ?? ""])
        return error
    }
    func submit(_ intent:ProcessClosureIntent)->ProcessClosureSubmission {
        guard intent.pid==pid else{return .rejected("Outside the test scope; no request was sent.")}
        let result=native.submit(intent)
        switch result {
        case .sent:record("sent",["pid":Int(intent.pid)])
        case .rejected(let reason):record("rejected",["pid":Int(intent.pid),"reason":reason])
        }
        return result
    }
    func observe(_ intent:ProcessClosureIntent)->ProcessClosureObservation {
        guard intent.pid==pid else{return .unreadable}
        let result=native.observe(intent)
        if case .exited=result {record("exitObserved",["pid":Int(intent.pid)])}
        return result
    }
    func clear(){native.clear()}
}

L10n.configure(AppLanguage(rawValue: ProcessInfo.processInfo.environment["TAWL_LANG"] ?? "en") ?? .english)

let args=CommandLine.arguments
guard args.count==3 else {fatalError("output directory and repository root required")}
let output=URL(fileURLWithPath:args[1]).standardizedFileURL
let root=URL(fileURLWithPath:args[2]).standardizedFileURL
let fixtureRoot=root.appendingPathComponent("work/native-closure-"+UUID().uuidString)
let app="Tawl Manual Fixture "+UUID().uuidString.prefix(8)
let executable=fixtureRoot.appendingPathComponent(app+".app/Contents/MacOS/fixture")
try FileManager.default.createDirectory(at:executable.deletingLastPathComponent(),withIntermediateDirectories:true)
defer {try? FileManager.default.removeItem(at:fixtureRoot)}
let compiler=Process();compiler.executableURL=URL(fileURLWithPath:"/usr/bin/clang")
compiler.arguments=["-Wall","-Wextra","-Werror",root.appendingPathComponent("Tests/Native/process_control_fixture.c").path,"-o",executable.path]
try compiler.run();compiler.waitUntilExit()
guard compiler.terminationStatus==0 else {fatalError("fixture compilation failed")}
let child=Process(),input=Pipe(),ready=Pipe()
child.executableURL=executable;child.arguments=["normal"]
child.standardInput=input;child.standardOutput=ready
try child.run()
defer {
    if child.isRunning {child.terminate()}
    child.waitUntilExit()
}
guard ready.fileHandleForReading.readData(ofLength:1)==Data("R".utf8) else {fatalError("fixture did not start")}
let logURL=output.appendingPathComponent("native-events.jsonl")
FileManager.default.createFile(atPath:logURL.path,contents:Data())
let log=try FileHandle(forWritingTo:logURL)
let controller=FixtureOnlyController(pid:child.processIdentifier,log:log)
controller.record("fixture",["pid":Int(child.processIdentifier),"app":app])
let collector=NativeCollector(),reducer=SnapshotReducer()
try TerminalUI(processController:controller).run(nextSnapshot:{
    let snapshot=reducer.reduce(collector.collect())
    if let own=snapshot.processes.first(where:{$0.pid==child.processIdentifier}) {
        controller.record("sample",["pid":Int(own.pid),"canReview":own.canReviewClosure==true,
                                     "footprint":own.footprintBytes ?? 0,
                                     "recommendations":assessProcess(own,snapshot:snapshot,history:[snapshot]).recommendations.count,
                                     "systemCPU":snapshot.cpuPercent.map{$0 as Any} ?? NSNull(),
                                     "pressure":snapshot.pressure.rawValue,
                                     "swap":snapshot.swapUsedBytes.map{$0 as Any} ?? NSNull()])
    }
    return snapshot
},interval:0.25)
// On early UI exit, ask only our own fixture to finish instead of waiting for its alarm.
if child.isRunning {try? input.fileHandleForWriting.write(contentsOf:Data("Q".utf8))}
child.waitUntilExit()
controller.record("childExit",["pid":Int(child.processIdentifier),"signal":Int(child.terminationStatus),
                              "uncaughtSignal":child.terminationReason == .uncaughtSignal])
