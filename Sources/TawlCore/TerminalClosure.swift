import Foundation

extension TerminalState {
    public mutating func beginClosure(using controller: ProcessClosureControlling, now: Double, candidate: ProcessSample? = nil) {
        guard closureSession == nil else { return }
        guard detailVisible || closureControlVisible, let process = candidate ?? selectedProcess, let snapshot = visibleSnapshot else {
            notice = L10n.text("Press x to open the termination panel; select a process."); return
        }
        switch prepareProcessClosure(process: process, snapshot: snapshot, assessment: assessment(for: process),
                                     now: now, isLive: !frozen && !historyVisible) {
        case .failure(let block): notice = block.message
        case .success(let intent):
            // prepare replaces the adapter's single native ticket. A prior report
            // keeps its metrics, but may no longer claim a verified target outcome.
            impactCanObserveNative = false; impactSession?.invalidateObservation()
            if let error = controller.prepare(intent) { controller.clear(); notice = error; return }
            closureSession = ProcessClosureSession(intent: intent); closureScroll = 0; impactVisible = false; notice = ""
        }
    }
    public mutating func chooseClosure(_ choice: ProcessClosureChoice) { closureSession?.choose(choice) }
    public mutating func dismissClosure(using controller: ProcessClosureControlling) {
        let pendingPreview = closureSession?.status == .preview
        closureSession?.cancel(); closureSession = nil; closureScroll = 0; impactVisible = false
        if pendingPreview || closureImpact == nil { controller.clear() }
    }
    public mutating func scrollClosure(by amount: Int, limit: Int) {
        closureScroll = min(max(0,limit), max(0,closureScroll+amount))
    }
    public mutating func confirmClosure(using controller: ProcessClosureControlling, now: Double, maximumScroll: Int = 0, measuredSnapshot: Snapshot? = nil) {
        guard var session = closureSession, let snapshot = measuredSnapshot ?? visibleSnapshot else { return }
        guard session.choice != .confirm || closureScroll >= maximumScroll else {
            notice = L10n.text("Scroll down and review all impact information first."); return
        }
        let process = snapshot.processes.first { $0.id == session.intent.processID }
        let assessment = process.map { self.assessment(for: $0, in: snapshot) } ?? ProcessAssessment()
        let result = session.consumeConfirmation(snapshot: snapshot, assessment: assessment, now: now,
                                                 isLive: !frozen && !historyVisible)
        // Publish the consumed state before invoking any side effect.
        closureSession = session
        if case .success(let intent) = result {
            let submission = controller.submit(intent)
            closureSession?.markSubmission(submission, now: now)
            if case .sent = submission {
                let wallTime = snapshot.timestamp.addingTimeInterval(now-snapshot.monotonicTime)
                closureImpact = ClosureImpact(intent:intent,startedAt:now,startedOn:wallTime,history:snapshots+[snapshot])
                impactSession = closureSession; impactCanObserveNative = true; impactVisible = true
            }
        }
        closureScroll = 0
    }
    public mutating func observeClosure(using controller: ProcessClosureControlling, now: Double) {
        guard let session = impactSession, impactCanObserveNative,
              [.waitingForExit, .stillRunning, .unverified].contains(session.status) else { return }
        impactSession?.observeNative(controller.observe(session.intent), now: now)
        if closureSession?.intent.processID == session.intent.processID {
            closureSession = impactSession
        }
        if closureImpact?.isComplete == true { impactCanObserveNative = false }
    }
    public mutating func captureImpact(_ snapshot: Snapshot, now: Double) { closureImpact?.observe(snapshot,now:now) }
    public mutating func advanceImpact(now: Double) { closureImpact?.advance(now:now) }
    public mutating func openImpact() {
        guard closureImpact != nil else { notice = L10n.text("No termination request has been sent; no comparison is available."); return }
        impactVisible = true; searchEditing = false; helpVisible = false
    }

}

extension TerminalRenderer {
    static func closureOutcome(_ status: ProcessClosureStatus) -> (String, String, TerminalInk) {
        switch status {
        case .preview: return (L10n.text("AWAITING CONFIRMATION"), L10n.text("No request sent yet. Cancel is selected by default."), .warning)
        case .cancelled: return (L10n.text("CANCELLED"), L10n.text("No request was sent to the process."), .secondary)
        case .submitting: return (L10n.text("VERIFYING IDENTITY"), L10n.text("Rechecking the target process and application."), .cpu)
        case .waitingForExit: return (L10n.text("REQUEST SENT · WAITING"), L10n.text("SIGTERM accepted; process exit has not been verified yet."), .warning)
        case .exitObserved: return (L10n.text("SELECTED PROCESS EXIT VERIFIED"), L10n.text("The original process identity is no longer running. The app may start another process."), .good)
        case .identityChanged: return (L10n.text("TARGET IDENTITY CHANGED"), L10n.text("Original identity no longer matches; no request sent to the new identity. Exit unverified."), .warning)
        case .stillRunning: return (L10n.text("PROCESS STILL RUNNING"), L10n.text("10 s elapsed. No forced termination; inspect the app through its own menu."), .warning)
        case .unverified: return (L10n.text("RESULT UNVERIFIED"), L10n.text("Process status cannot be read. No retry or forced termination was attempted."), .warning)
        case .rejected(let message): return (L10n.text("REQUEST NOT SENT"), message, .danger)
        }
    }
    static func closureView(_ c: inout TerminalCanvas, _ state: TerminalState) -> Int {
        guard let session = state.closureSession else { return 0 }
        let intent = session.intent, outcome = closureOutcome(session.status)
        let w = min(c.width-4, 100), x = (c.width-w)/2, y = 2
        let h = min(c.height-4, 20), inner = w-4
        c.fillRow(y: 0, fill: .panel)
        c.write(L10n.text(" TAWL / PROCESS TERMINATION · ") + (session.status == .preview ? L10n.text("2 CONFIRM"):L10n.text("3 RESULT")), x: 0, y: 0, ink: .cpu)
        c.box(x:x,y:y,width:w,height:h,title:outcome.0,ink:outcome.2)
        var doc = TerminalCanvas(width:inner,height:200), row = 0
        section(&doc,L10n.text("AFFECTED APPLICATION"),x:0,y:row,w:inner,ink:.cpu); row+=1
        row=paragraph(&doc,intent.applicationName,x:0,y:row,w:inner,ink:.primary)
        row=paragraph(&doc,"PID \(intent.pid) · \(intent.processName)",x:0,y:row,w:inner,ink:.secondary)
        row=paragraph(&doc,L10n.text("\(intent.applicationMemberCount) observed app processes · only 1 process targeted"),x:0,y:row,w:inner,ink:.muted)+1
        if session.status == .preview {
            row=paragraph(&doc,"◆ "+intent.reasons.joined(separator:" · "),x:0,y:row,w:inner,ink:.warning)
            row=paragraph(&doc,L10n.text("A tab, window or background task may stop; the entire app may be affected."),x:0,y:row,w:inner)+1
            row=paragraph(&doc,L10n.text("Unsaved changes may be lost. Save your work first."),x:0,y:row,w:inner,ink:.warning)
            row=paragraph(&doc,L10n.text("Method: SIGTERM · no guaranteed save dialog. No forced termination."),x:0,y:row,w:inner,ink:.muted)
            row=paragraph(&doc,L10n.text("No requests sent directly to other processes. Confirmation expires in 30 s."),x:0,y:row,w:inner,ink:.muted)
        } else {
            section(&doc,outcome.0,x:0,y:row,w:inner,ink:outcome.2); row+=1
            row=paragraph(&doc,outcome.1,x:0,y:row,w:inner,ink:outcome.2)+1
            row=paragraph(&doc,L10n.text("Scope: only PID \(intent.pid). This does not mean the entire application has closed."),x:0,y:row,w:inner)
            row=paragraph(&doc,L10n.text("Monitor memory pressure and swap writes. Reclaimed memory/swap is not guaranteed."),x:0,y:row+1,w:inner,ink:.muted)
        }
        let capacity = h-5, limit = max(0,row-capacity), offset = min(state.closureScroll,limit)
        c.copy(doc,fromRow:offset,toX:x+2,toY:y+1,rowCount:capacity)
        let buttonsY = y+h-3
        if session.status == .preview {
            let cancel = session.choice == .cancel, label = L10n.text("Send termination request"), ready = offset >= limit
            c.write(cancel ? L10n.text("› Cancel"):L10n.text("  Cancel"),x:x+2,y:buttonsY,ink:cancel ? .primary:.secondary,fill:cancel ? .selected:.panel)
            c.write((cancel ? "  ":"› ")+label,x:x+17,y:buttonsY,ink:ready ? (cancel ? .warning:.primary):.muted,fill:cancel ? .panel:.selected)
            c.write(ready ? L10n.text("←/→ or Tab select · Enter/Space apply · Esc cancel"):L10n.text("↑↓ Read all impact information before confirming."),x:x+2,y:buttonsY+1,ink:ready ? .muted:.warning)
        } else {
            c.write(L10n.text("Esc / Enter / Space: back to processes"),x:x+2,y:buttonsY,ink:.cpu)
            c.write(L10n.text("No automatic retries or SIGKILL."),x:x+2,y:buttonsY+1,ink:.muted)
        }
        c.fillRow(y:c.height-1,fill:.panel)
        c.write(limit>0 ? L10n.text(" ↑↓ / PgUp/PgDn scroll details · Esc back · q quit"):L10n.text(" Esc back · q quit"),x:0,y:c.height-1,ink:.secondary)
        if limit>0 { c.write(" \(offset+1)–\(min(row,offset+capacity))/\(row) ↑↓ ",x:x+w-22,y:y+h-1,ink:.cpu) }
        return limit
    }
}
