// Reproducible README frames from TAWL's production terminal renderer.
// This fixture does not inspect the host or send process-control signals.
// Build the package in debug mode, then link this script against TawlCore/CTawl.
import Foundation
@testable import TawlCore

private let width = 120
private let height = 32
private let gib = Double(1 << 30)
private let epoch = Date(timeIntervalSince1970: 1_735_689_600 + 11 * 3600 + 40 * 60)

private struct DemoFrame: Encodable {
    let durationMs: Int
    let caption: String
    let lines: [String]
}
private struct DemoDocument: Encodable {
    let width: Int
    let height: Int
    let synthetic: Bool
    let language: String
    let sequences: [String: [DemoFrame]]
}
private struct FictionalApp {
    let name: String
    // Known family identifiers exercise real category grouping with synthetic data.
    let family: String
    let project: String?
    let processName: String
    let count: Int
    let memoryGiB: Double
    let cpuCores: Double
}
private let apps: [FictionalApp] = [
    .init(name:"Model Runner",family:"app:demo-model-runner",project:"llm-lab",processName:"model-worker",count:4,memoryGiB:11.8,cpuCores:3.8),
    .init(name:"Browser",family:"com.apple.safari",project:nil,processName:"web-renderer",count:6,memoryGiB:4.4,cpuCores:0.8),
    .init(name:"Code Editor",family:"com.microsoft.vscode",project:"web-app",processName:"editor-worker",count:4,memoryGiB:1.7,cpuCores:0.3),
    .init(name:"Dev Server",family:"node",project:"web-app",processName:"node",count:2,memoryGiB:0.7,cpuCores:0.4),
    .init(name:"Database",family:"postgres",project:"api-service",processName:"postgres",count:3,memoryGiB:1.2,cpuCores:0.12),
    .init(name:"Team Chat",family:"com.tinyspeck.slackmacgap",project:nil,processName:"chat-worker",count:3,memoryGiB:0.8,cpuCores:0.06),
    .init(name:"Media Player",family:"music",project:nil,processName:"audio-player",count:2,memoryGiB:0.35,cpuCores:0.04),
    .init(name:"File Manager",family:"finder",project:nil,processName:"file-manager",count:1,memoryGiB:0.2,cpuCores:0.02),
    .init(name:"Terminal",family:"terminal",project:"api-service",processName:"terminal",count:1,memoryGiB:0.12,cpuCores:0.02),
    .init(name:"Image Studio",family:"photos",project:"design-assets",processName:"image-worker",count:2,memoryGiB:0.6,cpuCores:0.1),
    .init(name:"Notes",family:"demo.notes",project:nil,processName:"notes",count:1,memoryGiB:0.18,cpuCores:0.01),
    .init(name:"Sync Agent",family:"demo.sync",project:"research-notes",processName:"sync-worker",count:1,memoryGiB:0.08,cpuCores:0.03),
    .init(name:"Build Worker",family:"swift",project:"desktop-client",processName:"swift",count:2,memoryGiB:0.9,cpuCores:0.25),
    .init(name:"Document Viewer",family:"demo.documents",project:"research-notes",processName:"document-worker",count:2,memoryGiB:0.3,cpuCores:0.03)
]

private func snapshot(_ time: Double, afterTermination: Bool = false) -> Snapshot {
    var sample = Snapshot(timestamp:epoch.addingTimeInterval(time),monotonicTime:time)
    sample.intervalSeconds = 2
    sample.logicalCPUCount = 12
    sample.memoryTotalBytes = 32 << 30
    sample.pressure = afterTermination && time >= 128 ? .normal : .warning
    sample.compressedBytes = UInt64((afterTermination ? 3.3 : 4.8) * gib)
    // Intentionally unchanged: closing a process does not guarantee reclaimed swap.
    sample.swapUsedBytes = 6 << 30
    sample.swapInBytesPerSecond = afterTermination ? 0 : 80_000 + 30_000 * sin(time/11)
    sample.swapOutBytesPerSecond = afterTermination ? max(0,128-time) * 42_000 : 420_000 + 90_000 * sin(time/9)
    sample.networkInBytesPerSecond = 180_000 + 120_000 * (1 + sin(time/7))
    sample.networkOutBytesPerSecond = 30_000 + 16_000 * (1 + cos(time/9))
    sample.diskReadBytesPerSecond = (afterTermination ? 0.7 : 2.5) * 1_048_576 + 400_000 * (1 + sin(time/6))
    sample.diskWriteBytesPerSecond = 140_000 + (sample.swapOutBytesPerSecond ?? 0)
    sample.cpuCores = (0..<12).map { index in
        let base = afterTermination ? (index < 4 ? 20.0 : 27.0) : (index < 4 ? 32.0 : 73.0)
        let value = min(98,max(3,base + 10 * sin(time/8 + Double(index)*0.7)))
        return CPUCoreSample(id:index,kind:index < 4 ? .efficiency : .performance,utilizationPercent:value)
    }
    sample.cpuPercent = sample.cpuCores!.reduce(0) { $0 + ($1.utilizationPercent ?? 0) } / 12
    sample.gpus = [GPUSample(id:"demo-gpu",name:"Apple GPU",coreCount:32,utilizationPercent:afterTermination ? 9 + 4*sin(time/7) : 75 + 11*sin(time/9))]
    for (appIndex,app) in apps.enumerated() {
        let weights = app.count == 1 ? [1.0] : (0..<app.count).map { $0 == 0 ? 0.7 : 0.3/Double(app.count-1) }
        for member in 0..<app.count {
            let pid = Int32(4100 + appIndex*100 + member)
            if afterTermination && pid == 4100 { continue }
            let wave = 1 + 0.12*sin(time/8 + Double(appIndex))
            let bytes = UInt64(app.memoryGiB * weights[member] * gib + 2_000_000*(1+sin(time/13)))
            var process = ProcessSample(
                id:"\(pid):100",pid:pid,name:member == 0 ? app.processName : app.processName+" \(member+1)",
                applicationID:app.family,applicationName:app.name,
                projectID:app.project.map { "demo-project:"+$0 },projectName:app.project,projectEvidence:app.project == nil ? nil : "cwd",
                cpuCores:app.cpuCores * weights[member] * wave,footprintBytes:bytes,
                memoryDeltaBytes:Int64(120_000*sin(time/6 + Double(member))),
                diskReadBytesPerSecond:appIndex == 0 ? 150_000 : 0,diskWriteBytesPerSecond:appIndex == 0 ? 40_000 : 0,
                ageSeconds:14_400+time,canReviewClosure:true)
            if appIndex == 4 || appIndex == 7 || appIndex == 8 { process.canReviewClosure = false }
            sample.processes.append(process)
        }
    }
    sample.totalProcessCount = sample.processes.count
    return sample
}

private func populated() -> TerminalState {
    var state = TerminalState()
    for time in stride(from:0.0,through:120,by:2) { state.accept(snapshot(time)) }
    state.chooseSort(.footprint)
    return state
}
private func frame(_ state:TerminalState,_ caption:String,_ duration:Int = 850) -> DemoFrame {
    let rendered = TerminalRenderer.render(state,width:width,height:height)
    precondition(rendered.lines.count == height)
    precondition(rendered.lines.allSatisfy { TerminalText.width($0) == width })
    precondition(!rendered.lines.joined().contains("/Users/"))
    return DemoFrame(durationMs:duration,caption:caption,lines:rendered.coloredLines)
}

private func overview() -> [DemoFrame] {
    var state = populated()
    var frames: [DemoFrame] = []
    var now = 120.0
    func capture(_ caption:String,_ count:Int,_ duration:Int = 1000) {
        for _ in 0..<count {
            state.accept(snapshot(now));now += 2
            frames.append(frame(state,caption,duration))
        }
    }
    capture("Compare workloads by application",4)
    state.chooseSort(.cpu)
    capture("2  Sort by CPU usage",3)
    state.chooseSort(.footprint)
    capture("3  Sort by memory footprint",2)
    state.toggleHardware()
    capture("g  Reveal individual CPU cores and total GPU activity",4)
    state.toggleGrouping()
    capture("Tab  Group processes by project",3)
    state.toggleGrouping()
    capture("Tab  Compare usage categories",3)
    state.toggleGrouping()
    capture("Tab  Return to applications",3)
    precondition(frames.count == 22)
    return frames
}

/// Deliberately inert: only records the fake scenario's transitions.
/// There is no OS controller, signal call, or host process lookup in this script.
private final class DemoController: ProcessClosureControlling {
    var prepared: String?
    var submitted: [String] = []
    var exited = false
    func prepare(_ intent:ProcessClosureIntent) -> String? { prepared=intent.processID;return nil }
    func submit(_ intent:ProcessClosureIntent) -> ProcessClosureSubmission {
        precondition(intent.processID == prepared && intent.pid == 4100)
        submitted.append(intent.processID)
        return .sent
    }
    func observe(_ intent:ProcessClosureIntent) -> ProcessClosureObservation { exited ? .exited : .alive }
    func clear() { prepared=nil }
}

private func closure() -> [DemoFrame] {
    var state = populated()
    let controller = DemoController()
    var frames = [frame(state,"x  Review a resource-heavy process",1000)]
    state.openClosureControl(now:120)
    precondition(state.selectedControlRow?.process.pid == 4100)
    frames.append(frame(state,"Choose one process; see its affected application",1400))
    state.prepareControlledClosure(using:controller,now:120)
    precondition(state.closureSession?.choice == .cancel && controller.submitted.isEmpty)
    frames.append(frame(state,"Enter  Review impact; Cancel is the default",1800))
    let rendered = TerminalRenderer.render(state,width:width,height:height)
    state.scrollClosure(by:1000,limit:rendered.maximumDetailScroll)
    frames.append(frame(state,"Read the scope and save your work before continuing",1300))
    state.chooseClosure(.confirm)
    frames.append(frame(state,"Tab  Explicitly select Send termination request",1300))
    state.confirmClosure(using:controller,now:120,maximumScroll:rendered.maximumDetailScroll)
    precondition(state.impactVisible && controller.submitted == ["4100:100"])
    frames.append(frame(state,"Enter  Begin the before/after comparison",950))
    for time in stride(from:122.0,through:180,by:2) {
        let sample = snapshot(time,afterTermination:true)
        state.accept(sample)
        state.captureImpact(sample,now:time)
        controller.exited = true
        state.observeClosure(using:controller,now:time)
        if [124.0,132,144,156,168,180].contains(time) {
            let caption = time < 180 ? "Compare CPU, memory pressure, swap stock and swap writes" : "60-second result · swap stock remains unchanged · d exports HTML"
            frames.append(frame(state,caption,time == 180 ? 2400 : 1050))
        }
    }
    precondition(state.closureImpact?.isComplete == true)
    precondition(state.closureImpact?.summary.swapUsedDeltaBytes == 0)
    precondition(state.impactSession?.status == .exitObserved)
    precondition(frames.count == 12)
    return frames
}

L10n.configure(.english)
TerminalRenderer.clock.timeZone = TimeZone(secondsFromGMT:0)
private let document = DemoDocument(width:width,height:height,synthetic:true,language:"en",sequences:["overview":overview(),"closure":closure()])
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted,.sortedKeys,.withoutEscapingSlashes]
FileHandle.standardOutput.write(try encoder.encode(document))
FileHandle.standardOutput.write(Data([10]))
