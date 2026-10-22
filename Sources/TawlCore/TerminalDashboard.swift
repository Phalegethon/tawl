import Foundation

/// Presentation only: all measurements and findings retain their core meanings.
public enum TerminalRenderer {
    static let clock: DateFormatter = {
        let formatter=DateFormatter()
        formatter.locale=Locale(identifier:"en_US_POSIX")
        formatter.dateFormat="HH:mm:ss"
        return formatter
    }()
    static func time(_ d: Date) -> String { clock.string(from:d) }
    static func right(_ text: String, _ width: Int) -> String {
        let t=TerminalText.clipped(text,to:width)
        return String(repeating:" ",count:max(0,width-TerminalText.width(t)))+t
    }
    static func cores(_ n: Double?) -> String { n.map { String(format:"%.2f",$0) } ?? "—" }
    static func delta(_ n: Int64?) -> String {
        guard let n else { return "—" }
        return (n > 0 ? "+" : n < 0 ? "−" : "") + formatBytes(n.magnitude)
    }
    static func pressureInk(_ p: Pressure) -> TerminalInk {
        switch p { case .normal:return .good; case .warning:return .warning; case .critical:return .danger; case .unknown:return .muted }
    }
    static func meter(_ c:inout TerminalCanvas,_ fraction:Double?,x:Int,y:Int,width:Int,ink:TerminalInk) {
        for (i,glyph) in TerminalPlot.meter(fraction,width:width).enumerated() {
            c.write(glyph == "░" ? "─":String(glyph),x:x+i,y:y,ink:glyph == "░" ? .border:ink)
        }
    }
    static func recent(_ state: TerminalState) -> [Snapshot] {
        let samples=state.visibleHistory
        guard let last=samples.last else { return [] }
        return samples.filter { last.monotonicTime-$0.monotonicTime <= 120 }
    }
    // Sample-oriented plots explicitly mark a collection gap; no time interpolation or smoothing.
    static func values(_ samples: [Snapshot], _ key: (Snapshot)->Double?) -> [Double?] {
        var result:[Double?]=[]
        for (i,s) in samples.enumerated() {
            if i > 0 && s.monotonicTime-samples[i-1].monotonicTime > 5 { result.append(nil) }
            result.append(key(s))
        }
        return result
    }
    static func axis(_ samples:[Snapshot]) -> String {
        guard let first=samples.first,let last=samples.last else { return L10n.text("Waiting for history") }
        if samples.count < 2 { return L10n.text("Collecting history · · missing") }
        return L10n.text("\(time(first.timestamp))–\(time(last.timestamp)) · samples")
    }
    static func graph(_ c:inout TerminalCanvas,values:[Double?],x:Int,y:Int,width:Int,height:Int,ceiling:Double?,ink:TerminalInk) {
        for (i,line) in TerminalPlot.bars(values,width:width,height:height,ceiling:ceiling).enumerated() {
            c.write(line,x:x,y:y+i,ink:ink)
        }
    }
    static func cpuPanel(_ c:inout TerminalCanvas,_ s:Snapshot,_ history:[Snapshot],x:Int,y:Int,w:Int,h:Int) {
        c.box(x:x,y:y,width:w,height:h,title:"CPU",ink:.border)
        c.write("CPU",x:x+2,y:y,ink:.cpu)
        let n=s.cpuPercent.map{String(format:"%.1f%%",$0)} ?? L10n.text("measuring")
        c.write(n,x:x+2,y:y+1,ink:.cpu)
        c.write(right(s.logicalCPUCount>0 ? L10n.text("/ \(s.logicalCPUCount) cores"):L10n.text("cores —"),max(0,w-15)),x:x+13,y:y+1,ink:.muted)
        if h >= 8 {
            c.write(L10n.text("System total"),x:x+2,y:y+2,ink:.secondary)
            graph(&c,values:values(history,{$0.cpuPercent}),x:x+2,y:y+3,width:w-4,height:h-5,ceiling:100,ink:.cpu)
        } else {
            graph(&c,values:values(history,{$0.cpuPercent}),x:x+2,y:y+2,width:w-4,height:max(1,h-4),ceiling:100,ink:.cpu)
        }
        c.write(L10n.text("Scale 0–100%"),x:x+2,y:y+h-2,ink:.muted)
    }
    static func memoryPanel(_ c:inout TerminalCanvas,_ s:Snapshot,_ history:[Snapshot],x:Int,y:Int,w:Int,h:Int) {
        c.box(x:x,y:y,width:w,height:h,title:L10n.text("MEMORY"),ink:.border)
        c.write(L10n.text("MEMORY"),x:x+2,y:y,ink:.memory)
        c.write(pressureLabel(s.pressure).uppercased(with:L10n.locale),x:x+2,y:y+1,ink:pressureInk(s.pressure))
        c.write(TerminalText.clipped("Swap "+formatBytes(s.swapUsedBytes),to:w-4),x:x+2,y:y+2,ink:.secondary)
        if h >= 8 {
            c.write(TerminalText.clipped(L10n.text("Compressed ")+formatBytes(s.compressedBytes),to:w-4),x:x+2,y:y+3,ink:.muted)
            c.write(TerminalText.clipped(L10n.text("Swap out ")+formatRate(s.swapOutBytesPerSecond),to:w-4),x:x+2,y:y+4,ink:.secondary)
        }
        let stripY=y+h-3
        let pressure=values(history) { snap -> Double? in
            switch snap.pressure {case .normal:return 1;case .warning:return 4;case .critical:return 8;case .unknown:return nil}
        }
        for (i,glyph) in TerminalPlot.sparkline(pressure,width:w-4,ceiling:8).enumerated() {
            let ink:TerminalInk=glyph == "▁" ? .good:glyph == "▄" ? .warning:glyph == "█" ? .danger:.muted
            c.write(String(glyph),x:x+2+i,y:stripY,ink:ink)
        }
        c.write(w>=32 ? L10n.text("▁ normal  ▄ warning  █ critical"):L10n.text("▁ N   ▄ W   █ C"),x:x+2,y:y+h-2,ink:.muted)
    }
    static func ioPanel(_ c:inout TerminalCanvas,_ s:Snapshot,_ history:[Snapshot],network:Bool,x:Int,y:Int,w:Int,h:Int) {
        let ink:TerminalInk=network ? .network:.disk
        let title=network ? L10n.text("NETWORK"):"DISK"
        let down:(Snapshot)->Double? = network ? {$0.networkInBytesPerSecond}:{$0.diskReadBytesPerSecond}
        let up:(Snapshot)->Double? = network ? {$0.networkOutBytesPerSecond}:{$0.diskWriteBytesPerSecond}
        let a=values(history,down),b=values(history,up)
        let maximum=max((a+b).compactMap{$0}.max() ?? 0,1)
        c.box(x:x,y:y,width:w,height:h,title:title,ink:.border);c.write(title,x:x+2,y:y,ink:ink)
        c.write(TerminalText.clipped("↓ "+formatRate(down(s)),to:w-4),x:x+2,y:y+1,ink:ink)
        c.write(TerminalPlot.sparkline(a,width:w-4,ceiling:maximum),x:x+2,y:y+2,ink:ink)
        c.write(TerminalText.clipped("↑ "+formatRate(up(s)),to:w-4),x:x+2,y:y+3,ink:.secondary)
        c.write(TerminalPlot.sparkline(b,width:w-4,ceiling:maximum),x:x+2,y:y+4,ink:ink)
        if h>=9 { c.write(network ? L10n.text("↓ receive  ↑ send"):L10n.text("↓ read  ↑ write"),x:x+2,y:y+5,ink:.muted) }
        let scale=(a+b).contains{$0 != nil} ? L10n.text("Scale 0–")+formatRate(maximum):L10n.text("Waiting for scale")
        c.write(TerminalText.clipped(scale,to:w-4),x:x+2,y:y+h-2,ink:.muted)
    }
    static func groupValues(_ history:[Snapshot],id:String,grouping:Grouping,memory:Bool)->[Double?] {
        values(history) { sample in
            let members=sample.processes.filter { workloadGroupIdentity(for:$0,by:grouping).id == id }
            guard !members.isEmpty else {return nil}
            let numbers:[Double]=memory ? members.compactMap{$0.footprintBytes.map {Double($0)}}:members.compactMap(\.cpuCores)
            guard numbers.count == members.count else {return nil}
            return numbers.reduce(0,+)
        }
    }
    static func inspector(_ c:inout TerminalCanvas,_ state:TerminalState,_ history:[Snapshot],x:Int,y:Int,w:Int,h:Int) {
        c.box(x:x,y:y,width:w,height:h,title:L10n.text("SELECTED WORKLOAD"),ink:.border)
        guard let selected=state.selectedWorkload else {
            c.write(L10n.text("Select a workload."),x:x+2,y:y+2,ink:.muted);return
        }
        let inner=w-4
        var line=y+1
        let nameLines=TerminalText.wrapped(selected.name,to:inner)
        for text in nameLines.prefix(3) {c.write(text,x:x+2,y:line,ink:.primary);line+=1}
        if state.selectedIsMissing {c.write(L10n.text("NOT IN THIS SAMPLE · last values"),x:x+2,y:line,ink:.warning);line+=1}
        c.write(L10n.text("\(selected.memberIDs.count) processes · Enter details"),x:x+2,y:line,ink:.muted);line+=2
        let cpu=groupValues(history,id:selected.id,grouping:state.grouping,memory:false)
        let mem=groupValues(history,id:selected.id,grouping:state.grouping,memory:true)
        let graphHeight=h>=28 ? 3:2
        if line+graphHeight+8<y+h {
            c.write("CPU",x:x+2,y:line,ink:.cpu)
            c.write(right(cores(selected.cpuCores)+(selected.unknownCPUCount>0 ? "*":"")+L10n.text(" cores"),inner-5),x:x+7,y:line,ink:.cpu);line+=1
            graph(&c,values:cpu,x:x+2,y:line,width:inner,height:graphHeight,ceiling:max(cpu.compactMap{$0}.max() ?? 0,1),ink:.cpu);line+=graphHeight
            c.write(cpu.contains{$0 != nil} ? L10n.text("0–\(cores(max(cpu.compactMap{$0}.max() ?? 0,1))) cores · auto"):L10n.text("Waiting for scale"),x:x+2,y:line,ink:.muted);line+=2
            c.write(L10n.text("FOOTPRINT"),x:x+2,y:line,ink:.memory)
            c.write(right(formatBytes(selected.footprintBytes)+(selected.unknownMemoryCount>0 ? "*":""),inner-9),x:x+11,y:line,ink:.memory);line+=1
            graph(&c,values:mem,x:x+2,y:line,width:inner,height:graphHeight,ceiling:nil,ink:.memory);line+=graphHeight
            let peak=mem.compactMap{$0}.max().flatMap { value -> UInt64? in
                guard value.isFinite,value>=0,value<Double(UInt64.max) else {return nil}
                return UInt64(value)
            }
            c.write(TerminalText.clipped(peak.map{L10n.text("0–\(formatBytes($0)) · auto")} ?? L10n.text("Waiting for scale"),to:inner),x:x+2,y:line,ink:.muted);line+=1
        }
        if line<y+h-1 {c.write(TerminalText.clipped(L10n.text("Last change  ")+delta(selected.memoryDeltaBytes),to:inner),x:x+2,y:line,ink:.secondary);line+=2}
        if line<y+h-1 {c.write(TerminalText.clipped(axis(history),to:inner),x:x+2,y:line,ink:.muted);line+=2}
        if selected.unknownCPUCount>0 || selected.unknownMemoryCount>0 {
            if line<y+h-1 {c.write(TerminalText.clipped(L10n.text("Partial: \(selected.unknownCPUCount) CPU / \(selected.unknownMemoryCount) memory"),to:inner),x:x+2,y:line,ink:.warning);line+=2}
        }
        if line+3<y+h-1 {
            let memoryOrder=state.effectiveSort == .footprint || state.effectiveSort == .memoryDelta
            c.write(memoryOrder ? L10n.text("TOP PROCESSES · FOOTPRINT"):L10n.text("TOP PROCESSES · CPU CORES"),x:x+2,y:line,ink:.secondary);line+=1
            for member in state.selectedMembers.prefix(min(6,max(0,y+h-line-5))) {
                let name=TerminalText.padded("\(member.pid) "+member.name,to:inner-12)
                c.write(name,x:x+2,y:line,ink:.secondary)
                c.write(right(memoryOrder ? formatBytes(member.footprintBytes):cores(member.cpuCores),11),x:x+w-13,y:line,ink:memoryOrder ? .memory:.cpu);line+=1
            }
            line+=1
        }
        let notes=[state.grouping == .project ? L10n.text("Project: working-directory evidence. Unknown workloads are kept separate."):state.grouping == .category ? L10n.text("Category: estimated from known app families. Actual purpose is not measured."):L10n.text("Application family: executable and live parent chain."),L10n.text("Footprint is not RAM percentage. High usage alone does not prove a cause.")]
        for note in notes {
            for text in TerminalText.wrapped(note,to:inner) where line<y+h-1 { c.write(text,x:x+2,y:line,ink:.muted);line+=1 }
            line+=1
        }
    }
    public static func render(_ state:TerminalState,width:Int,height:Int)->TerminalFrame {
        var c=TerminalCanvas(width:width,height:height)
        guard width>0,height>0 else {return TerminalFrame(lines:[],visibleRowIDs:[])}
        func finish(_ c:TerminalCanvas,_ ids:[String]=[],_ limit:Int=0)->TerminalFrame {
            TerminalFrame(lines:c.lines,visibleRowIDs:ids,maximumDetailScroll:limit,coloredLines:c.ansiLines())
        }
        guard width>=80,height>=24 else {
            c.write(L10n.text("TAWL · Terminal must be at least 80×24."),x:1,y:1,ink:.warning)
            c.write(L10n.text("Enlarge the window or use tawl status."),x:1,y:3)
            c.write(L10n.text("Live collection continues. q: quit"),x:1,y:min(5,height-1),ink:.muted);return finish(c)
        }
        if state.impactExportVisible {impactExportView(&c,state);return finish(c)}
        if state.impactVisible, state.closureImpact != nil {impactView(&c,state);return finish(c)}
        if state.closureSession != nil {let limit=closureView(&c,state);return finish(c,[],limit)}
        if state.closureControlVisible {return finishControl(&c,state)}
        guard let s=state.visibleSnapshot else {c.write(L10n.text("TAWL · Waiting for first sample…"),x:1,y:1,ink:.cpu);return finish(c)}
        let history=recent(state),findings=analyze(state.visibleHistory)
        let rows=state.workloads
        let mode=state.historyVisible ? L10n.text("HISTORY"):state.frozen ? L10n.text("FROZEN"):L10n.text("LIVE")
        c.fillRow(y:0,fill:.panel)
        c.write(" TAWL",x:0,y:0,ink:.cpu)
        c.write(" / \(mode)",x:7,y:0,ink:state.frozen || state.historyVisible ? .warning:.good)
        c.write("  "+(state.recordingActive ? L10n.text("RECORDING"):L10n.text("SESSION MEMORY")),x:10+TerminalText.width(mode),y:0,ink:state.recordingActive ? .danger:.muted)
        let stamp=time(s.timestamp)+(state.frozen || state.historyVisible ? L10n.text(" · collection continues"):L10n.text(" · 2 s samples"))
        c.write(right(stamp,36),x:width-37,y:0,ink:.secondary)
        let observed=findings.first(where:{$0.severity != "info"})?.title ?? findings.first?.title ?? L10n.text("First sample")
        c.write(TerminalText.clipped(observed,to:width-40),x:1,y:1,ink:pressureInk(s.pressure))
        c.write(right(L10n.text("\(s.processes.count)/\(s.totalProcessCount) processes · \(s.unreadableProcessCount) unavailable"),36),x:width-37,y:1,ink:.muted)
        c.write(TerminalText.clipped(axis(history)+L10n.text(" history · chart columns show peaks, · missing"),to:width-2),x:1,y:2,ink:.muted)
        let compact=width<96
        let panelHeight=compact ? 6:height>=36 ? 9:7
        var bodyY=3+panelHeight
        if !state.helpVisible && !state.detailVisible && !state.memoryFocus && state.hardwareVisible {
            bodyY = hardwarePanel(&c,state,s,history,y:3)
        } else if !state.helpVisible && !state.detailVisible && state.memoryFocus && width<120 {
            swapBand(&c,state,y:3,w:width,h:9);bodyY=12
        } else if !state.helpVisible && !state.detailVisible {
            if compact {
                let half=width/2
                cpuPanel(&c,s,history,x:0,y:3,w:half,h:panelHeight)
                memoryPanel(&c,s,history,x:half,y:3,w:width-half,h:panelHeight)
                c.write(TerminalText.clipped("Disk ↓\(formatRate(s.diskReadBytesPerSecond)) ↑\(formatRate(s.diskWriteBytesPerSecond))",to:half-2),x:1,y:bodyY,ink:.disk)
                c.write(TerminalText.clipped(L10n.text("Net ↓\(formatRate(s.networkInBytesPerSecond)) ↑\(formatRate(s.networkOutBytesPerSecond))"),to:width-half-2),x:half+1,y:bodyY,ink:.network)
                bodyY+=1
            } else {
                let part=width/4
                cpuPanel(&c,s,history,x:0,y:3,w:part,h:panelHeight)
                memoryPanel(&c,s,history,x:part,y:3,w:part,h:panelHeight)
                ioPanel(&c,s,history,network:false,x:part*2,y:3,w:part,h:panelHeight)
                ioPanel(&c,s,history,network:true,x:part*3,y:3,w:width-part*3,h:panelHeight)
            }
        } else {bodyY=3}
        let bottom=height-3,bodyHeight=bottom-bodyY
        var ids:[String]=[],limit=0
        if state.helpVisible {
            c.box(x:0,y:bodyY,width:width,height:bodyHeight,title:L10n.text("CONTROLS"),ink:.cpu)
            let help=[L10n.text("↑/↓ j/k      Select workload or process"), L10n.text("Enter / i    Processes → selected process assessment"), L10n.text("Tab          Applications → Projects → Categories"), L10n.text("o            Review candidates / all processes in selected group"), L10n.text("x            Termination panel · select / review / confirm"), L10n.text("g            Show or hide CPU cores / GPU view"), L10n.text("[ / ]        Hardware page · access all cores / devices"), L10n.text("b            Memory / swap inspection · footprint order"), L10n.text("e            Last comparison · d: save HTML from that view"), L10n.text("1 2 3 4 5    Sort name / CPU / footprint / Δ memory / members"), L10n.text("Same key     Change direction · r reverse · 0 auto · s next"), L10n.text("/            Search · Enter apply · Esc clear"), L10n.text("h ←/→        History and samples · Space freeze"), L10n.text("m            Add event marker at live time"), L10n.text("PgUp/PgDn    Large step · Home/End first/last"), L10n.text("Esc          Return to previous view · q / Ctrl-C quit"), "", L10n.text("CPU! ≥1 core (red ≥2) · RAM! ≥2 GiB (red ≥4)"), L10n.text("Δ! ≥100 MiB increase in last sample · not a diagnosis."), L10n.text("* partial total · · missing sample · memory bars are relative"), L10n.text("Verified live app + explicit confirmation: SIGTERM to one process."), L10n.text("Low activity: age ≥2 hours + ≥10 min CPU/disk observation."), L10n.text("Window/keyboard use and per-process network use are not measured.")]
            for (i,line) in help.prefix(bodyHeight-2).enumerated(){c.write(line,x:2,y:bodyY+1+i,ink:i>10 ? .muted:.secondary)}
        } else if state.detailVisible {
            let result=processView(&c,state,bodyY:bodyY,bottom:bottom)
            ids=result.ids;limit=result.limit
        } else {
            let inspectorWidth=width>=120 ? min(54,max(40,width/3)):0
            let tableWidth=width-inspectorWidth
            let group=state.grouping.title.uppercased(with:L10n.locale)
            let title=L10n.text("\(state.memoryFocus ? L10n.text("MEMORY CANDIDATES"):group) · \(rows.count) workloads · \(sortTitle(state))")
            c.box(x:0,y:bodyY,width:tableWidth,height:bodyHeight,title:title,ink:.border)
            c.write(TerminalText.clipped(title,to:tableWidth-4),x:2,y:bodyY,ink:.secondary)
            let bar=tableWidth>=98 ? 7:4
            let inner=tableWidth-4
            let memoryWidth=12,countWidth=10
            let nameWidth=inner-(8+1+bar+1+memoryWidth+1+bar+1+11+countWidth)
            let cpuX=2+nameWidth,memX=cpuX+8+1+bar+1,deltaX=memX+memoryWidth+1+bar+1,countX=deltaX+11
            c.fillRow(y:bodyY+1,from:1,to:tableWidth-1,fill:.panel)
            c.write(sortHeader(L10n.text("1 WORKLOAD"),.name,state),x:2,y:bodyY+1,ink:.secondary)
            c.write(right(sortHeader("2 CPU",.cpu,state),8),x:cpuX,y:bodyY+1,ink:.cpu)
            c.write(right(sortHeader(L10n.text("3 FOOTPRINT"),.footprint,state),memoryWidth),x:memX,y:bodyY+1,ink:.memory)
            c.write(right(sortHeader(L10n.text("4 Δ MEMORY"),.memoryDelta,state),11),x:deltaX,y:bodyY+1,ink:.muted)
            c.write(right(sortHeader(L10n.text("5 MEMBERS"),.members,state),countWidth),x:countX,y:bodyY+1,ink:.muted)
            let capacity=max(1,bodyHeight-3),selectedIndex=rows.firstIndex{$0.id==state.selectedID} ?? 0
            let start=min(max(0,selectedIndex-capacity+1),max(0,rows.count-capacity))
            let peak=Double(rows.compactMap(\.footprintBytes).max() ?? 1)
            for (i,row) in rows.dropFirst(start).prefix(capacity).enumerated() {
                let y=bodyY+2+i,selected=row.id==state.selectedID
                if selected {c.fillRow(y:y,from:1,to:tableWidth-1,fill:.selected)}
                let signals=resourceSignals(cpuCores:row.cpuCores,footprintBytes:row.footprintBytes,memoryDeltaBytes:row.memoryDeltaBytes)
                resourceName(&c,name:row.name,signals:signals,selected:selected,x:2,y:y,width:nameWidth)
                c.write(right(cores(row.cpuCores)+(row.unknownCPUCount>0 ? "*":""),8),x:cpuX,y:y,ink:resourceInk(signals,.cpu,normal:(row.cpuCores ?? 0)>0.01 ? .cpu:.muted))
                let cpuFraction=s.logicalCPUCount>0 ? row.cpuCores.map{$0/Double(s.logicalCPUCount)}:nil
                meter(&c,cpuFraction,x:cpuX+9,y:y,width:bar,ink:.cpu)
                c.write(right(formatBytes(row.footprintBytes)+(row.unknownMemoryCount>0 ? "*":""),memoryWidth),x:memX,y:y,ink:resourceInk(signals,.memory,normal:.primary))
                meter(&c,row.footprintBytes.map{Double($0)/max(1,peak)},x:memX+memoryWidth+1,y:y,width:bar,ink:.memory)
                c.write(right(delta(row.memoryDeltaBytes),11),x:deltaX,y:y,ink:resourceInk(signals,.growth,normal:(row.memoryDeltaBytes ?? 0)<0 ? .good:.muted))
                c.write(right(String(row.memberIDs.count),countWidth),x:countX,y:y,ink:.secondary);ids.append(row.id)
            }
            if rows.isEmpty {c.write(TerminalText.clipped(state.query.isEmpty ? L10n.text("No readable workloads; check visibility coverage."):L10n.text("No search matches. Esc: clear"),to:tableWidth-4),x:2,y:bodyY+3,ink:.muted)}
            if inspectorWidth>0 {
                if state.memoryFocus {swapInspector(&c,state,x:tableWidth,y:bodyY,w:inspectorWidth,h:bodyHeight)}
                else {inspector(&c,state,history,x:tableWidth,y:bodyY,w:inspectorWidth,h:bodyHeight)}
            }
            if rows.count>capacity {c.write(" \(start+1)–\(min(start+capacity,rows.count))/\(rows.count) ",x:max(2,tableWidth-20),y:bottom-1,ink:.muted)}
        }
        let sessionCount=state.snapshots.count
        let sessionStart=state.snapshots.first.map{time($0.timestamp)} ?? "—"
        let timeline=state.historyVisible ? L10n.text("HISTORY · ←/→ sample · h live"):L10n.text("\(sessionStart) · \(sessionCount) samples")
        c.write(TerminalText.clipped(timeline+(state.closureImpact == nil ? L10n.text(" · Tab: Applications / Projects / Categories"):L10n.text(" · e: last termination comparison")),to:width-2),x:1,y:bottom,ink:.muted)
        if state.searchEditing {c.write(L10n.text("SEARCH /\(state.query)▏  Enter apply · Esc clear"),x:1,y:bottom+1,ink:.cpu)}
        else if !state.query.isEmpty {c.write(TerminalText.clipped(L10n.text("Filter /\(state.query) · \(rows.count) matches · Esc clear"),to:width-2),x:1,y:bottom+1,ink:.cpu)}
        else if !state.notice.isEmpty {c.write(TerminalText.clipped(state.notice,to:width-2),x:1,y:bottom+1,ink:.warning)}
        else if let notice = state.updateNotice {c.write(TerminalText.clipped(notice,to:width-2),x:1,y:bottom+1,ink:.good)}
        else if state.selectedIsMissing {c.write(L10n.text("Selected workload is missing. Enter: last observed details"),x:1,y:bottom+1,ink:.warning)}
        else {
            let guide=state.memoryFocus ? L10n.text("Footprint ≠ swap share · RAM→disk: new writes · b/Esc back"):state.processInfoVisible ? L10n.text("x: termination panel · eligibility and application impact"):state.detailVisible ? L10n.text("1 Name  2 CPU(cores)  3 Footprint  4 Δ Memory · r reverse · 0 auto · ! high · * partial"):L10n.text("1 Name  2 CPU(cores)  3 Footprint  4 Δ Memory  5 Members · r reverse · 0 auto · ! high")
            c.write(TerminalText.clipped(guide,to:width-2),x:1,y:bottom+1,ink:.muted)
        }
        c.fillRow(y:height-1,fill:.panel)
        let controls=state.memoryFocus ? L10n.text(" ↑↓ select  Enter processes  b/Esc back  1–5 sort  ? help  q quit"):state.processInfoVisible ? L10n.text(" ↑↓ scroll  x termination  b swap  Esc processes  q quit"):state.detailVisible ? L10n.text(" ↑↓ process  Enter evidence  o review  x terminate  1–4 sort  Esc  ?  q quit"):state.helpVisible ? L10n.text(" Esc back  ? close  q quit"):L10n.text(" ↑↓ select  Enter info  Tab group  x close  g CPU/GPU  b swap  / find  ?  q quit")
        c.write(TerminalText.clipped(controls,to:width),x:0,y:height-1,ink:.secondary)
        return finish(c,ids,limit)
    }
}
