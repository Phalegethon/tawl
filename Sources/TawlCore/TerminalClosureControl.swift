import Foundation

public struct ClosureControlRow {
    public let process:ProcessSample
    public let block:ProcessClosureBlock?
    public let reasons:[String]
    public var eligible:Bool {block == nil}
    var badge:String {
        switch block {
        case nil:return reasons.isEmpty ? L10n.text("MANUAL"):L10n.text("SUGGESTED")
        case .noRecommendation:return L10n.text("No advice")
        case .protectedProcess:return L10n.text("Protected")
        case .notLive:return L10n.text("Needs live")
        case .staleSample:return L10n.text("Stale sample")
        case .ownershipUnknown:return L10n.text("Uncertain")
        default:return L10n.text("Changed")
        }
    }
}

extension TerminalState {
    public var closureControlRows:[ClosureControlRow] {
        guard let snapshot=visibleSnapshot else{return []}
        let source=closureControlAll ? snapshot.processes:selectedMembers
        return source.compactMap {process -> ClosureControlRow? in
            let assessment=assessment(for:process)
            if closureControlAll && assessment.recommendations.isEmpty {return nil}
            let block:ProcessClosureBlock?
            switch prepareProcessClosure(process:process,snapshot:snapshot,assessment:assessment,
                                         now:closureControlNow,isLive:!frozen && !historyVisible) {
            case .success:block=nil
            case .failure(let failure):block=failure
            }
            return ClosureControlRow(process:process,block:block,reasons:assessment.recommendations.map(\.title))
        }.sorted {
            if $0.eligible != $1.eligible {return $0.eligible}
            if $0.reasons.isEmpty != $1.reasons.isEmpty {return !$0.reasons.isEmpty}
            if $0.process.footprintBytes != $1.process.footprintBytes {return ($0.process.footprintBytes ?? 0)>($1.process.footprintBytes ?? 0)}
            return $0.process.pid<$1.process.pid
        }
    }
    public var selectedControlRow:ClosureControlRow? {closureControlRows.first{$0.process.id==closureControlSelectedID}}
    public mutating func openClosureControl(now:Double) {
        closureControlVisible=true;closureControlAll=false;closureControlMessage="";closureControlFailedID=nil;closureControlNow=now
        helpVisible=false;searchEditing=false
        closureControlSelectedID=detailVisible ? selectedProcess?.id:closureControlRows.first?.process.id
    }
    public mutating func closeClosureControl() {
        closureControlVisible=false;closureControlMessage="";closureControlFailedID=nil
    }
    public mutating func moveClosureControl(by amount:Int) {
        let rows=closureControlRows
        guard !rows.isEmpty else{return}
        let index=rows.firstIndex{$0.process.id==closureControlSelectedID} ?? (amount<0 ? rows.count:-1)
        closureControlSelectedID=rows[min(rows.count-1,max(0,index+amount))].process.id
        closureControlMessage="";closureControlFailedID=nil
    }
    public mutating func toggleClosureControlScope() {
        closureControlAll.toggle();closureControlMessage="";closureControlFailedID=nil
        closureControlSelectedID=closureControlRows.first?.process.id
    }
    public mutating func prepareControlledClosure(using controller:ProcessClosureControlling,now:Double) {
        closureControlNow=now;closureControlFailedID=nil
        guard let row=selectedControlRow else {
            closureControlMessage=L10n.text("Selected process is missing from this sample. ↑↓ to select a current process.");return
        }
        if let block=row.block {closureControlMessage=block.message;return}
        beginClosure(using:controller,now:now,candidate:row.process)
        if closureSession == nil {closureControlMessage=notice;closureControlFailedID=row.process.id}
        else {closureControlMessage=""}
    }
}

extension TerminalRenderer {
    static func closureControlView(_ c:inout TerminalCanvas,_ state:TerminalState)->[String] {
        let rows=state.closureControlRows
        let w=min(c.width-4,118),h=min(c.height-4,max(20,min(44,rows.count+13))),x=(c.width-w)/2,y=2,inner=w-4
        let chosen=rows.first{$0.process.id==state.closureControlSelectedID}
        let failedID=state.closureControlFailedID
        let failed=rows.contains{$0.process.id==failedID}
        let recommended=rows.filter{$0.eligible && $0.process.id != failedID && !$0.reasons.isEmpty}.count
        let manual=rows.filter{$0.eligible && $0.process.id != failedID && $0.reasons.isEmpty}.count
        c.fillRow(y:0,fill:.panel)
        c.write(L10n.text(" TAWL / PROCESS TERMINATION"),x:0,y:0,ink:.cpu)
        c.box(x:x,y:y,width:w,height:h,title:L10n.text("PROCESS TERMINATION"),ink:.cpu)
        c.write(L10n.text("1 SELECT PROCESS  →  2 REVIEW IMPACT / CONFIRM  →  3 RESULT"),x:x+2,y:y+1,ink:.cpu)
        let scope=state.closureControlAll ? L10n.text("Recommendations across all applications"):L10n.text("Selected workload: ")+(state.selectedWorkload?.name ?? L10n.text("None"))
        c.write(TerminalText.clipped(scope,to:inner),x:x+2,y:y+2,ink:.primary)
        let mode=state.historyVisible || state.frozen ? L10n.text(" · HISTORY/FROZEN: live data required"):L10n.text(" · LIVE")
        c.write(L10n.text("\(rows.count) processes · \(recommended) suggested · \(manual) manual")+(failed ? L10n.text(" · 1 blocked"):"")+mode,x:x+2,y:y+3,ink:state.historyVisible || state.frozen ? .warning:.secondary)
        let nameWidth=inner-41,cpuX=x+2+9+nameWidth,memX=cpuX+8,statusX=memX+12
        c.fillRow(y:y+4,from:x+1,to:x+w-1,fill:.panel)
        c.write(L10n.text("  PID    PROCESS"),x:x+2,y:y+4,ink:.secondary)
        c.write(right(L10n.text("CPU cr."),8),x:cpuX,y:y+4,ink:.cpu)
        c.write(right(L10n.text("FOOTPRINT"),12),x:memX,y:y+4,ink:.memory)
        c.write(L10n.text(" STATUS"),x:statusX,y:y+4,ink:.secondary)
        let capacity=max(1,h-13),selectedIndex=rows.firstIndex{$0.process.id==state.closureControlSelectedID} ?? 0
        let start=min(max(0,selectedIndex-capacity+1),max(0,rows.count-capacity))
        var ids:[String]=[]
        for (i,row) in rows.dropFirst(start).prefix(capacity).enumerated() {
            let cy=y+5+i,p=row.process,selected=p.id==state.closureControlSelectedID
            if selected {c.fillRow(y:cy,from:x+1,to:x+w-1,fill:.selected)}
            c.write((selected ? "›":" ")+right(String(p.pid),6)+"  ",x:x+2,y:cy,ink:selected ? .primary:.secondary)
            c.write(TerminalText.clipped(p.name,to:nameWidth),x:x+11,y:cy,ink:row.eligible ? .primary:.muted)
            c.write(right(cores(p.cpuCores),8),x:cpuX,y:cy,ink:.cpu)
            c.write(right(formatBytes(p.footprintBytes),12),x:memX,y:cy,ink:.memory)
            let nativeFailed=p.id==failedID
            c.write(" "+(nativeFailed ? L10n.text("BLOCKED"):row.badge),x:statusX,y:cy,ink:nativeFailed ? .danger:row.eligible ? (row.reasons.isEmpty ? .cpu:.warning):.muted)
            ids.append(p.id)
        }
        if rows.isEmpty {
            c.write(L10n.text("No review candidates in this scope."),x:x+2,y:y+6,ink:.warning)
            c.write(L10n.text("Tab to change scope; measurements continue."),x:x+2,y:y+7,ink:.secondary)
        }
        let base=y+h-7
        c.write(String(repeating:"─",count:inner),x:x+2,y:base-1,ink:.border)
        if let chosen {
            let p=chosen.process
            c.write(TerminalText.clipped(L10n.text("Affected application: ")+p.applicationName,to:inner),x:x+2,y:base,ink:.primary)
            c.write(TerminalText.clipped(L10n.text("Only PID \(p.pid) · ")+p.name,to:inner),x:x+2,y:base+1,ink:.secondary)
        }
        var reason = !state.closureControlMessage.isEmpty ? state.closureControlMessage:
            chosen?.block?.message ?? chosen?.reasons.joined(separator:" · ") ?? L10n.text("↑↓ select process. Tab: selected workload / all recommendations.")
        if chosen?.eligible == true && chosen?.reasons.isEmpty == true && state.closureControlMessage.isEmpty {
            reason = L10n.text("Manual selection: no automatic recommendation. You can confirm termination.")
        }
        for (i,line) in TerminalText.wrapped(reason,to:inner).prefix(2).enumerated() {
            c.write(line,x:x+2,y:base+2+i,ink:failed ? .danger:chosen?.eligible == true && state.closureControlMessage.isEmpty ? .warning:.secondary)
        }
        let action:String
        if state.historyVisible && state.frozen {action=L10n.text("Esc to return; h, then Space to resume live samples.")}
        else if state.historyVisible {action=L10n.text("Esc to return; h to resume live samples.")}
        else if state.frozen {action=L10n.text("Esc to return; Space to resume live samples.")}
        else if failed {action=L10n.text("Enter / i: retry · ↑↓ select another process")}
        else {action=chosen?.eligible == true ? L10n.text("Enter / i: review impact and continue to confirmation"):L10n.text("Termination unavailable for this process · ↑↓ select another")}
        c.write(TerminalText.clipped(action,to:inner),x:x+2,y:y+h-3,ink:chosen?.eligible == true ? .cpu:.muted)
        c.write(L10n.text("Tab scope · Esc back · e last comparison · q quit"),x:x+2,y:y+h-2,ink:.secondary)
        if rows.count>capacity {c.write(" \(start+1)–\(min(rows.count,start+capacity))/\(rows.count) ",x:x+w-20,y:y+h-1,ink:.muted)}
        c.fillRow(y:c.height-1,fill:.panel)
        c.write(L10n.text(" ↑↓ select · Enter / i review · Tab scope · Esc back · q quit"),x:0,y:c.height-1,ink:.secondary)
        return ids
    }
    static func finishControl(_ c:inout TerminalCanvas,_ state:TerminalState)->TerminalFrame {
        let ids=closureControlView(&c,state)
        return TerminalFrame(lines:c.lines,visibleRowIDs:ids,coloredLines:c.ansiLines())
    }
}
