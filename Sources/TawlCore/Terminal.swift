import Foundation
import CTawl

/// Plain terminal cells only. Untrusted labels never become terminal commands.
public enum TerminalText {
    public static func sanitize(_ value: String) -> String {
        let scalars = Array(value.unicodeScalars)
        var result = String.UnicodeScalarView()
        var i = 0
        while i < scalars.count {
            let n = scalars[i].value
            if n == 27 || n == 0x9b || n == 0x9d || n == 0x90 {
                var kind = n
                i += 1
                if n == 27 {
                    guard i < scalars.count else { break }
                    kind = scalars[i].value; i += 1
                }
                if kind == 91 || kind == 0x9b {
                    while i < scalars.count {
                        let current = scalars[i].value; i += 1
                        if (0x40...0x7e).contains(current) { break }
                    }
                } else if [93,80,94,95,0x9d,0x90].contains(kind) {
                    while i < scalars.count {
                        let current = scalars[i].value; i += 1
                        if current == 7 || current == 0x9c { break }
                        if current == 27 && i < scalars.count && scalars[i].value == 92 { i += 1; break }
                    }
                }
                continue
            }
            i += 1
            if n == 9 || n == 10 || n == 13 { result.append(" "); continue }
            if n < 32 || (0x7f...0x9f).contains(n) || (0x202a...0x202e).contains(n) || (0x2066...0x2069).contains(n) { continue }
            result.append(scalars[i-1])
        }
        return String(result)
    }

    private static func cells(_ character: Character) -> Int {
        let scalars = Array(character.unicodeScalars)
        // Emoji sequences, skin tones, flags and variation selectors occupy one glyph.
        if scalars.contains(where: { $0.properties.isEmojiPresentation || $0.value == 0xfe0f || $0.value == 0x20e3 }) { return 2 }
        var result = 0
        for scalar in scalars {
            let n = scalar.value
            switch scalar.properties.generalCategory {
            case .nonspacingMark, .enclosingMark, .format, .control: continue
            default: break
            }
            let wide = (0x1100...0x115f).contains(n) || (0x2329...0x232a).contains(n) ||
                (0x2e80...0xa4cf).contains(n) || (0xac00...0xd7a3).contains(n) ||
                (0xf900...0xfaff).contains(n) || (0xfe10...0xfe19).contains(n) ||
                (0xfe30...0xfe6f).contains(n) || (0xff00...0xff60).contains(n) ||
                (0xffe0...0xffe6).contains(n) || (0x20000...0x3fffd).contains(n)
            result += wide ? 2 : 1
        }
        return result
    }
    public static func width(_ value: String) -> Int { sanitize(value).reduce(0) { $0 + cells($1) } }
    public static func clipped(_ value: String, to columns: Int) -> String {
        guard columns > 0 else { return "" }
        let text = sanitize(value)
        guard width(text) > columns else { return text }
        var result = "", used = 0
        for character in text {
            let size = cells(character)
            if used + size > columns - 1 { break }
            result.append(character); used += size
        }
        return result + "…"
    }
    public static func padded(_ value: String, to columns: Int) -> String {
        let text = clipped(value, to: columns)
        return text + String(repeating: " ", count: max(0, columns - width(text)))
    }
    public static func wrapped(_ value: String, to columns: Int) -> [String] {
        guard columns > 0 else { return [] }
        var result: [String] = [], line = "", used = 0
        for character in sanitize(value) {
            let size = cells(character)
            if used + size > columns && !line.isEmpty {
                if let space=line.lastIndex(of:" "),space>line.startIndex {
                    result.append(String(line[..<space]))
                    line=String(line[line.index(after:space)...]);used=width(line)
                } else {result.append(line);line="";used=0}
            }
            if character == " " && line.isEmpty {continue}
            if size <= columns { line.append(character); used += size }
        }
        if !line.isEmpty { result.append(line) }
        return result.isEmpty ? [""] : result
    }
}

public struct TerminalFrame {
    public var lines: [String]
    public var visibleRowIDs: [String]
    public var maximumDetailScroll: Int = 0
    public var coloredLines: [String] = []
}

/// Display state is independent of collection; pinned frames survive history eviction.
public struct TerminalState {
    private let history = SessionHistory()
    private var evidenceTracker = ProcessEvidenceTracker()
    private var frozenSnapshot: Snapshot?
    private var historicalSnapshot: Snapshot?
    private var frozenHistory: [Snapshot] = []
    private var historicalHistory: [Snapshot] = []
    private var frozenEvidence: ProcessEvidenceTracker?
    private var historicalEvidence: ProcessEvidenceTracker?
    private var retainedWorkload: Workload?
    private var retainedMembers: [ProcessSample] = []
    public private(set) var selectedID: String?
    public private(set) var grouping: Grouping = .application
    public private(set) var sort: WorkloadSort = .automatic
    public private(set) var sortDirection: SortDirection = .descending
    public private(set) var selectedProcessID: String?
    private var retainedProcess: ProcessSample?
    public private(set) var query = ""
    public var detailVisible = false
    public var processInfoVisible = false
    public private(set) var recommendationsOnly = false
    public private(set) var memoryFocus = false
    public var helpVisible = false
    public var searchEditing = false
    public var detailScroll = 0
    public var notice = ""
    public var updateNotice: String?
    public var recordingActive = false
    public var hardwareVisible = false
    public var hardwarePage = 0
    public internal(set) var closureSession: ProcessClosureSession?
    public internal(set) var closureScroll = 0
    public internal(set) var closureImpact: ClosureImpact?
    public internal(set) var impactSession: ProcessClosureSession?
    public internal(set) var impactVisible = false
    var impactCanObserveNative = false
    public internal(set) var closureControlVisible = false
    public internal(set) var closureControlAll = false
    public internal(set) var closureControlSelectedID: String?
    public internal(set) var closureControlMessage = ""
    var closureControlFailedID: String?
    var closureControlNow = 0.0
    public internal(set) var impactExportVisible = false
    public internal(set) var impactExportURL: URL?
    public internal(set) var impactExportError = ""
    public init() {}
    public mutating func toggleHardware() {
        if detailVisible || memoryFocus { hardwareVisible = true }
        else { hardwareVisible.toggle() }
        detailVisible = false; processInfoVisible = false; memoryFocus = false
    }
    public mutating func moveHardwarePage(by amount:Int,width:Int,height:Int) {
        guard hardwareVisible && !detailVisible && !memoryFocus,let snapshot=visibleSnapshot else{return}
        let layout=HardwareLayout(snapshot:snapshot,width:width,height:height)
        let current=min(max(0,hardwarePage),layout.pages-1)
        hardwarePage=min(layout.pages-1,max(0,current+amount))
    }
    public var snapshots: [Snapshot] { history.snapshots }
    public var markers: [EventMarker] { history.markers }
    public var frozen: Bool { frozenSnapshot != nil }
    public var historyVisible: Bool { historicalSnapshot != nil }
    public var visibleSnapshot: Snapshot? { historicalSnapshot ?? frozenSnapshot ?? snapshots.last }
    public var workloads: [Workload] {
        guard let snapshot = visibleSnapshot else { return [] }
        let values = sortedWorkloads(groupProcesses(snapshot, by: grouping),sort:sort,direction:sortDirection,snapshot:snapshot)
        return query.isEmpty ? values : values.filter { TerminalText.sanitize($0.name).localizedCaseInsensitiveContains(query) }
    }
    public var selectedWorkload: Workload? { workloads.first { $0.id == selectedID } ?? retainedWorkload }
    public var selectedIsMissing: Bool {
        selectedID != nil && !(visibleSnapshot.map { groupProcesses($0, by: grouping).contains { $0.id == selectedID } } ?? false)
    }
    public var selectedMembers: [ProcessSample] {
        guard !selectedIsMissing, let snapshot = visibleSnapshot, let workload = selectedWorkload else { return sortedProcesses(retainedMembers,sort:effectiveSort,direction:sortDirection) }
        let members = Set(workload.memberIDs)
        return sortedProcesses(snapshot.processes.filter { members.contains($0.id) },sort:effectiveSort,direction:sortDirection)
    }
    public var effectiveSort: WorkloadSort {
        if sort != .automatic {return sort}
        let pressure=visibleSnapshot?.pressure
        return pressure == .warning || pressure == .critical ? .footprint:.cpu
    }
    public var selectedProcess: ProcessSample? {
        guard let id=selectedProcessID else {return visibleProcesses.first}
        return selectedMembers.first{$0.id==id} ?? retainedProcess
    }
    public func assessment(for process:ProcessSample, in measuredSnapshot:Snapshot? = nil)->ProcessAssessment {
        guard let snapshot=measuredSnapshot ?? visibleSnapshot else {return ProcessAssessment()}
        let tracker:ProcessEvidenceTracker?=historyVisible ? historicalEvidence:frozen ? frozenEvidence:evidenceTracker
        let evidence=tracker?.evidence(for:process,at:snapshot)
        return assessProcess(process,snapshot:snapshot,history:evidence == nil ? visibleHistory:[],evidence:evidence)
    }
    public var visibleProcesses:[ProcessSample] {
        let members=selectedMembers
        return recommendationsOnly ? members.filter{!assessment(for:$0).recommendations.isEmpty}:members
    }
    public mutating func toggleRecommendations() {
        recommendationsOnly.toggle();processInfoVisible=false;detailScroll=0
        selectedProcessID=visibleProcesses.first?.id;retainedProcess=visibleProcesses.first
    }
    public var selectedProcessIsMissing: Bool {
        guard let process=selectedProcess else {return false}
        return !(visibleSnapshot?.processes.contains{$0.id==process.id} ?? false)
    }
    public mutating func chooseSort(_ key: WorkloadSort) {
        if sort==key && key != .automatic {reverseSort()}
        else {sort=key;sortDirection=key == .name ? .ascending:.descending}
        retainSelection()
    }
    public mutating func reverseSort() {
        if sort == .automatic {sort=effectiveSort}
        sortDirection=sortDirection == .ascending ? .descending:.ascending
    }
    public mutating func navigate(by amount:Int,detailLimit:Int) {
        if processInfoVisible {scrollDetails(by:amount,limit:detailLimit)}
        else if detailVisible {moveProcess(by:amount)}
        else {moveSelection(by:amount)}
    }
    public mutating func cycleSort() {
        let all=WorkloadSort.allCases.filter{!detailVisible || $0 != .members}
        chooseSort(all[((all.firstIndex(of:sort) ?? 0)+1)%all.count])
    }
    public mutating func openDetails() {
        memoryFocus=false
        detailVisible=true;processInfoVisible=false;recommendationsOnly=false;detailScroll=0
        selectedProcessID=selectedMembers.first?.id;retainedProcess=selectedMembers.first
    }
    public mutating func moveProcess(by amount:Int) {
        let rows=visibleProcesses
        guard !rows.isEmpty else {return}
        let index=rows.firstIndex{$0.id==selectedProcessID} ?? (amount < 0 ? rows.count:-1)
        let next=rows[min(rows.count-1,max(0,index+amount))]
        selectedProcessID=next.id;retainedProcess=next;detailScroll=0
    }
    public var visibleHistory: [Snapshot] {
        if historyVisible { return historicalHistory }
        if frozen { return frozenHistory }
        guard let snapshot = visibleSnapshot else { return [] }
        let values = snapshots.filter { $0.monotonicTime <= snapshot.monotonicTime }
        return values.isEmpty ? [snapshot] : values
    }
    private func pinnedWindow(endingAt snapshot: Snapshot?) -> [Snapshot] {
        guard let snapshot else { return [] }
        // Retain only the displayed two-minute window, with an 8 MiB encoded-payload
        // budget per pinned mode. This is a retention bound, not an exact RSS limit.
        var remaining = 8 * 1024 * 1024
        var retained: [Snapshot] = []
        let encoder = JSONEncoder()
        for sample in snapshots.reversed() {
            if sample.monotonicTime > snapshot.monotonicTime { continue }
            if snapshot.monotonicTime - sample.monotonicTime > 120 { break }
            guard let data = try? encoder.encode(sample), data.count <= remaining else { break }
            retained.append(sample)
            remaining -= data.count
        }
        // The selected frame is already retained independently. If it exceeds the
        // history budget, preserve that frame alone without adding older samples.
        return retained.isEmpty ? [snapshot] : Array(retained.reversed())
    }
    private mutating func retainSelection() {
        let rows = workloads
        if selectedID == nil { selectedID = rows.first?.id }
        if let current = rows.first(where: { $0.id == selectedID }) {
            retainedWorkload = current
            let ids = Set(current.memberIDs)
            retainedMembers = visibleSnapshot?.processes.filter { ids.contains($0.id) } ?? []
        }
        if let process=selectedMembers.first(where:{$0.id==selectedProcessID}) {retainedProcess=process}
        if detailVisible && recommendationsOnly {
            let visible=visibleProcesses
            if !visible.contains(where:{$0.id==selectedProcessID}) {
                selectedProcessID=visible.first?.id;retainedProcess=visible.first
            }
        }
    }
    public mutating func accept(_ snapshot: Snapshot) {
        evidenceTracker.update(snapshot)
        history.append(snapshot)
        retainSelection()
    }
    public mutating func mark(_ marker: EventMarker) { history.mark(marker) }
    public mutating func moveSelection(by amount: Int) {
        let rows = workloads
        guard !rows.isEmpty else { return }
        let index = rows.firstIndex { $0.id == selectedID } ?? (amount < 0 ? rows.count : -1)
        selectedID = rows[min(rows.count-1, max(0, index + amount))].id
        detailScroll = 0; retainSelection()
    }
    public mutating func scrollDetails(by amount: Int, limit: Int) {
        detailScroll = min(max(0,limit), max(0,min(detailScroll,max(0,limit)) + amount))
    }
    public mutating func toggleGrouping() {
        memoryFocus=false
        switch grouping {case .application:grouping = .project;case .project:grouping = .category;case .category:grouping = .application}
        selectedID = nil; retainedWorkload = nil; retainedMembers = []; detailVisible = false; detailScroll = 0
        selectedProcessID=nil;retainedProcess=nil;processInfoVisible=false
        recommendationsOnly=false
        retainSelection()
    }
    public mutating func toggleMemoryFocus() {
        memoryFocus.toggle();detailVisible=false;processInfoVisible=false;recommendationsOnly=false
        detailScroll=0
        if memoryFocus {
            grouping = .application;sort = .footprint;sortDirection = .descending
            query="";searchEditing=false
            selectedID=nil;retainedWorkload=nil;retainedMembers=[]
            selectedProcessID=nil;retainedProcess=nil
        }
        retainSelection()
    }
    public mutating func setSearch(_ query: String) {
        self.query = String(TerminalText.sanitize(query).prefix(160))
        if !workloads.contains(where: { $0.id == selectedID }) {
            selectedID = nil; retainedWorkload = nil; retainedMembers = []
        }
        retainSelection()
    }
    public mutating func toggleFrozen() {
        if historyVisible {
            frozenSnapshot = historicalSnapshot
            frozenHistory = historicalHistory
            frozenEvidence = historicalEvidence
            historicalSnapshot = nil
            historicalHistory = []
            historicalEvidence = nil
        } else if frozen {
            frozenSnapshot = nil
            frozenHistory = []
            frozenEvidence = nil
        } else {
            frozenSnapshot = visibleSnapshot
            frozenHistory = pinnedWindow(endingAt: frozenSnapshot)
            frozenEvidence = evidenceTracker
        }
        retainSelection()
    }
    public mutating func toggleHistory() {
        if historyVisible {
            historicalSnapshot = nil
            historicalHistory = []
            historicalEvidence = nil
        } else {
            historicalSnapshot = visibleSnapshot
            historicalHistory = frozen ? frozenHistory : pinnedWindow(endingAt: historicalSnapshot)
            historicalEvidence = frozen ? frozenEvidence:evidenceTracker
        }
        retainSelection()
    }
    public mutating func moveHistory(by amount: Int) {
        guard let current = historicalSnapshot, !snapshots.isEmpty else { return }
        let index = snapshots.lastIndex { $0.monotonicTime <= current.monotonicTime } ?? 0
        let target = min(snapshots.count-1, max(0, index + amount))
        notice = amount < 0 && index == 0 ? L10n.text("No recordings before this time.") : ""
        historicalSnapshot = snapshots[target]
        historicalHistory = pinnedWindow(endingAt: historicalSnapshot)
        if historicalSnapshot?.monotonicTime == snapshots.last?.monotonicTime {historicalEvidence=evidenceTracker}
        else if historicalSnapshot?.monotonicTime != current.monotonicTime {historicalEvidence=nil}
        retainSelection()
    }
}

public enum TerminalKey: Equatable {
    case up, down, left, right, pageUp, pageDown, home, end, enter, backspace, escape, tab, space
    case text(String)
}
public struct TerminalInput {
    private var pending: [UInt8] = []
    private var pendingLineFeed = false
    private var pasting = false
    private var pasteEndMatched = 0
    private let pasteEnd: [UInt8] = [27, 91, 50, 48, 49, 126]
    public init() {}
    private func wheelKey(_ button: Int) -> TerminalKey? {
        // Shift/Alt/Ctrl bits do not change wheel direction. Horizontal wheel,
        // movement, button presses and releases are deliberately ignored.
        switch button & ~28 {
        case 64: return .up
        case 65: return .down
        default: return nil
        }
    }
    public mutating func feed(_ bytes: [UInt8]) -> [TerminalKey] {
        var result: [TerminalKey] = []
        // Parse incrementally so even a very large paste never becomes a queued
        // command buffer. While pasting, retain only an end-delimiter position.
        for incoming in bytes {
            // CRLF is one Return, including when the two bytes arrive in
            // separate reads. Repeated CR keys still remain separate actions.
            if pendingLineFeed {
                pendingLineFeed = false
                if incoming == 10 { continue }
            }
            if pasting {
                if incoming == pasteEnd[pasteEndMatched] {
                    pasteEndMatched += 1
                    if pasteEndMatched == pasteEnd.count { pasting = false; pasteEndMatched = 0 }
                } else { pasteEndMatched = incoming == 27 ? 1 : 0 }
                continue
            }
            pending.append(incoming)
            while let byte = pending.first {
                if byte == 27 {
                    if pending.count == 1 { break }
                    if pending[1] == 91 || pending[1] == 79 {
                        // Legacy X10 reports have three raw payload bytes after M.
                        // Consume the entire report, even if a coordinate is 'q'.
                        if pending[1] == 91 && pending.count >= 3 && pending[2] == 77 {
                            guard pending.count >= 6 else { break }
                            if pending[3] >= 32, let key = wheelKey(Int(pending[3])-32) { result.append(key) }
                            pending.removeFirst(6); continue
                        }
                        guard let end = pending.indices.dropFirst(2).first(where: { (64...126).contains(pending[$0]) }) else { break }
                        let sequence = String(decoding:pending[2...end],as:UTF8.self)
                        if pending[1] == 91 && sequence == "200~" {
                            pending.removeFirst(end+1); pasting = true; pasteEndMatched = 0; break
                        }
                        if pending[1] == 91 && sequence.first == "<" {
                            let fields = sequence.dropFirst().dropLast().split(separator:";",omittingEmptySubsequences:false)
                            if sequence.last == "M", fields.count == 3,
                               let button = Int(fields[0]), (0...255).contains(button),
                               let x = Int(fields[1]), x > 0, let y = Int(fields[2]), y > 0,
                               let key = wheelKey(button) { result.append(key) }
                            pending.removeFirst(end+1); continue
                        }
                        let keys: [String: TerminalKey] = ["A":.up,"B":.down,"C":.right,"D":.left,"H":.home,"F":.end,"1~":.home,"4~":.end,"5~":.pageUp,"6~":.pageDown,"1;2A":.up,"1;2B":.down]
                        if pending[1] == 79 && sequence == "M" { result.append(.enter) }
                        else if let key = keys[sequence] { result.append(key) }
                        pending.removeFirst(end+1); continue
                    }
                    pending.removeFirst(); result.append(.escape); continue
                }
                let keys: [UInt8:TerminalKey] = [9:.tab,10:.enter,13:.enter,127:.backspace,8:.backspace,32:.space]
                if let key = keys[byte] {
                    pending.removeFirst(); result.append(key)
                    pendingLineFeed = byte == 13
                    continue
                }
                if byte < 32 { pending.removeFirst(); continue }
                let count = byte < 128 ? 1 : byte >= 0xc2 && byte <= 0xdf ? 2 : byte >= 0xe0 && byte <= 0xef ? 3 : byte >= 0xf0 && byte <= 0xf4 ? 4 : 1
                guard pending.count >= count else { break }
                if let text = String(bytes: pending.prefix(count),encoding:.utf8) { result.append(.text(text)) }
                pending.removeFirst(count)
            }
            if pending.count > 64 { pending.removeAll() }
        }
        return result
    }
    public mutating func flushEscape() -> [TerminalKey] {
        guard !pasting else { return [] }
        guard pending == [27] else { return [] }
        pending.removeAll(); return [.escape]
    }
}

public enum TerminalError: Error, LocalizedError {
    case requiresTTY, setupFailed, invalidInterval
    public var errorDescription: String? {
        switch self {
        case .requiresTTY: return L10n.text("Live view requires an interactive terminal. Use tawl status instead.")
        case .setupFailed: return L10n.text("Could not read or change terminal input settings.")
        case .invalidInterval: return L10n.text("Sampling interval must be positive and finite.")
        }
    }
}

public final class TerminalUI {
    private let processController: ProcessClosureControlling
    public init(processController: ProcessClosureControlling = NativeProcessController()) {
        self.processController = processController
    }
    /// Absolute row positioning never sends a linefeed at the lower margin,
    /// including when the window shrinks between size measurement and write.
    static func screenOutput(_ frame: TerminalFrame, colors: Bool) -> String {
        var text = ""
        for (index, line) in frame.lines.enumerated() {
            text += "\u{1b}[\(index+1);1H"
            text += colors && frame.coloredLines.indices.contains(index) ? frame.coloredLines[index] : line
        }
        return text
    }
    public func run(nextSnapshot: () throws -> Snapshot, onSnapshot: ((Snapshot) throws -> Void)? = nil, onMarker: ((EventMarker) throws -> Void)? = nil, interval: TimeInterval = 2, recordingActive: Bool = false, updateNotice: (() -> String?)? = nil) throws {
        guard interval.isFinite, interval > 0 else { throw TerminalError.invalidInterval }
        guard tawl_terminal_is_tty() != 0 else { throw TerminalError.requiresTTY }
        guard tawl_terminal_begin() == 0 else { throw TerminalError.setupFailed }
        defer { processController.clear(); tawl_terminal_end() }
        var state = TerminalState(), input = TerminalInput()
        state.recordingActive = recordingActive
        state.hardwareVisible = true
        var nextSample = ProcessInfo.processInfo.systemUptime
        var dirty = true, quitting = false
        var detailLimit = 0
        var previousWidth: Int32 = 0, previousHeight: Int32 = 0
        let colors = ProcessInfo.processInfo.environment["NO_COLOR"] == nil
        var buffer = [UInt8](repeating:0,count:256)
        while !quitting && tawl_terminal_stopped() == 0 {
            let latestNotice = updateNotice?()
            if latestNotice != state.updateNotice { state.updateNotice = latestNotice; dirty = true }
            let now = ProcessInfo.processInfo.systemUptime
            if now >= nextSample {
                let snapshot = try nextSnapshot()
                state.accept(snapshot); try onSnapshot?(snapshot)
                state.captureImpact(snapshot, now: ProcessInfo.processInfo.systemUptime)
                state.observeClosure(using: processController, now: ProcessInfo.processInfo.systemUptime)
                nextSample = ProcessInfo.processInfo.systemUptime + interval; dirty = true
            }
            let priorElapsed = Int(state.closureImpact?.elapsed ?? 0)
            state.closureControlNow = ProcessInfo.processInfo.systemUptime
            state.advanceImpact(now: ProcessInfo.processInfo.systemUptime)
            if state.impactVisible && Int(state.closureImpact?.elapsed ?? 0) != priorElapsed { dirty = true }
            var width: Int32 = 80, height: Int32 = 24
            tawl_terminal_size(&width,&height)
            if width != previousWidth || height != previousHeight { dirty = true; previousWidth = width; previousHeight = height }
            if dirty {
                let frame = TerminalRenderer.render(state,width:Int(width),height:Int(height))
                detailLimit = frame.maximumDetailScroll
                if state.closureSession != nil { state.scrollClosure(by:0,limit:detailLimit) }
                else { state.scrollDetails(by:0,limit:detailLimit) }
                let text = Self.screenOutput(frame, colors:colors)
                FileHandle.standardOutput.write(Data(text.utf8)); dirty = false
            }
            let count = tawl_terminal_read(&buffer,Int32(buffer.count),100)
            if count < 0 { break }
            let keys = count > 0 ? input.feed(Array(buffer.prefix(Int(count)))) : input.flushEscape()
            for key in keys {
                dirty = true
                if state.impactExportVisible {
                    if key == .text("q") {quitting=true}
                    else if key == .escape || key == .enter {state.impactExportVisible=false}
                    else if key == .text("a") {state.openExportedImpact()}
                    else if key == .text("d"), state.impactExportURL == nil, width >= 80 && height >= 24 {state.exportImpact()}
                    break
                }
                if state.impactVisible {
                    if key == .text("q") { quitting = true }
                    else if key == .escape || key == .enter { state.dismissClosure(using: processController) }
                    else if key == .text("d"), width >= 80 && height >= 24 {state.exportImpact()}
                    break
                }
                if let closure = state.closureSession {
                    if key == .text("q") { quitting = true; break }
                    if key == .escape { state.dismissClosure(using: processController); break }
                    // Never act on a confirmation that is hidden by a small viewport.
                    guard width >= 80 && height >= 24 else { continue }
                    switch key {
                    case .left: state.chooseClosure(.cancel)
                    case .right: state.chooseClosure(.confirm)
                    case .tab: state.chooseClosure(closure.choice == .cancel ? .confirm:.cancel)
                    case .up: state.scrollClosure(by:-1,limit:detailLimit)
                    case .down: state.scrollClosure(by:1,limit:detailLimit)
                    case .pageUp: state.scrollClosure(by:-10,limit:detailLimit)
                    case .pageDown: state.scrollClosure(by:10,limit:detailLimit)
                    case .enter, .space:
                        if closure.status != .preview || closure.choice == .cancel {
                            state.dismissClosure(using: processController)
                        } else {
                            // Collect again immediately before authorization. A changed
                            // ownership or lifetime invalidates the immutable preview.
                            let fresh = try nextSnapshot()
                            state.accept(fresh); try onSnapshot?(fresh)
                            state.captureImpact(fresh, now: ProcessInfo.processInfo.systemUptime)
                            state.confirmClosure(using: processController, now: ProcessInfo.processInfo.systemUptime, maximumScroll: detailLimit, measuredSnapshot: fresh)
                            nextSample = ProcessInfo.processInfo.systemUptime + interval
                        }
                    default: break
                    }
                    // Render each modal transition before accepting another input batch.
                    break
                }
                if state.closureControlVisible {
                    if key == .text("q") {quitting=true;break}
                    if key == .escape {state.closeClosureControl();break}
                    guard width >= 80 && height >= 24 else {continue}
                    switch key {
                    case .up, .text("k"):state.moveClosureControl(by:-1)
                    case .down, .text("j"):state.moveClosureControl(by:1)
                    case .pageUp:state.moveClosureControl(by:-10)
                    case .pageDown:state.moveClosureControl(by:10)
                    case .home:state.moveClosureControl(by:-1_000_000)
                    case .end:state.moveClosureControl(by:1_000_000)
                    case .tab:state.toggleClosureControlScope()
                    case .enter, .text("i"):state.prepareControlledClosure(using:processController,now:ProcessInfo.processInfo.systemUptime)
                    case .text("e"):
                        state.openImpact()
                        if !state.impactVisible {state.closureControlMessage=state.notice}
                    default:break
                    }
                    break
                }
                if state.searchEditing {
                    switch key {
                    case .escape: state.setSearch(""); state.searchEditing = false
                    case .enter: state.searchEditing = false
                    case .backspace: state.setSearch(String(state.query.dropLast()))
                    case .space: state.setSearch(state.query + " ")
                    case .text(let text): state.setSearch(state.query + text)
                    default: break
                    }
                    continue
                }
                if state.helpVisible {
                    if key == .escape || key == .text("?") { state.helpVisible = false }
                    else if key == .text("q") { quitting = true }
                    continue
                }
                switch key {
                case .text("q"): quitting = true
                case .up, .text("k"):
                    state.navigate(by:-1,detailLimit:detailLimit)
                case .down, .text("j"):
                    state.navigate(by:1,detailLimit:detailLimit)
                case .pageUp:
                    state.navigate(by:-10,detailLimit:detailLimit)
                case .pageDown:
                    state.navigate(by:10,detailLimit:detailLimit)
                case .home:
                    state.navigate(by:-1_000_000,detailLimit:detailLimit)
                case .end:
                    state.navigate(by:1_000_000,detailLimit:detailLimit)
                case .left: state.moveHistory(by:-1)
                case .right: state.moveHistory(by:1)
                case .enter, .text("i"):
                    if state.detailVisible {state.processInfoVisible=true;state.detailScroll=0}
                    else {state.openDetails()}
                case .tab: state.toggleGrouping()
                case .text("b"): state.toggleMemoryFocus()
                case .text("g"): state.toggleHardware()
                case .text("["), .text("]"):
                    state.moveHardwarePage(by:key == .text("]") ? 1 : -1,width:Int(width),height:Int(height))
                case .text("e"): state.openImpact()
                case .text("x"):
                    guard width >= 80 && height >= 24 else { continue }
                    state.openClosureControl(now: ProcessInfo.processInfo.systemUptime)
                    break
                case .text("0"): state.chooseSort(.automatic)
                case .text("1"): state.chooseSort(.name)
                case .text("2"): state.chooseSort(.cpu)
                case .text("3"): state.chooseSort(.footprint)
                case .text("4"): state.chooseSort(.memoryDelta)
                case .text("5"):
                    if !state.detailVisible {state.chooseSort(.members)}
                    else {state.notice=L10n.text("Member count is sorted in the groups view.")}
                case .text("s"): state.cycleSort()
                case .text("o"):
                    if !state.detailVisible {state.openDetails()}
                    state.toggleRecommendations()
                case .text("r"): state.reverseSort()
                case .space: state.toggleFrozen()
                case .text("h"): state.toggleHistory()
                case .text("/"): state.searchEditing = true; state.detailVisible = false;state.processInfoVisible=false
                case .text("?"): state.helpVisible = true
                case .text("m"):
                    let marker = EventMarker(); state.mark(marker); try onMarker?(marker)
                    state.notice = L10n.text("Event marked at live time · inspect nearby samples with ←/→ in history.")
                case .escape:
                    state.notice = ""
                    if state.processInfoVisible {state.processInfoVisible=false}
                    else if state.detailVisible { state.detailVisible = false }
                    else if state.memoryFocus { state.toggleMemoryFocus() }
                    else if state.historyVisible { state.toggleHistory() }
                    else if state.frozen { state.toggleFrozen() }
                    else if !state.query.isEmpty { state.setSearch("") }
                default: break
                }
                if state.closureSession != nil || state.closureControlVisible { break }
            }
        }
    }
}
