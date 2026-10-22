import Foundation

extension TerminalRenderer {
    static func resourceSummary(_ p:ProcessSample,_ a:ProcessAssessment)->String {
        let label=signalLabel(a.signals)
        if !label.isEmpty {return L10n.text("RESOURCE ALERT  ")+label}
        guard let cpu=p.cpuCores,cpu.isFinite,cpu>=0,p.footprintBytes != nil,p.memoryDeltaBytes != nil else {
            return L10n.text("Missing measurements · high usage cannot be fully assessed")
        }
        return L10n.text("High usage threshold not exceeded.")
    }
    static func quickAction(_ state:TerminalState,_ a:ProcessAssessment)->String {
        if state.selectedProcessIsMissing {return L10n.text("No current process; no action is recommended for this PID.")}
        if state.frozen || state.historyVisible {return L10n.text("Return to live view and verify this process; this is historical data.")}
        if a.quietObservationState == .protected {return L10n.text("Review dependent workloads in their service or VM application.")}
        if !a.recommendations.isEmpty {
            return L10n.text("Save your work first. x: affected application and termination approval.")
        }
        return L10n.text("No termination recommendation; monitor usage and observation time.")
    }
    static func section(_ c:inout TerminalCanvas,_ title:String,x:Int,y:Int,w:Int,ink:TerminalInk = .primary) {
        c.fillRow(y:y,from:x,to:x+w,fill:.panel)
        c.write(TerminalText.clipped(title,to:w),x:x,y:y,ink:ink)
    }
    @discardableResult
    static func paragraph(_ c:inout TerminalCanvas,_ text:String,x:Int,y:Int,w:Int,ink:TerminalInk = .secondary)->Int {
        let lines=TerminalText.wrapped(text,to:w)
        for (i,line) in lines.enumerated(){c.write(line,x:x,y:y+i,ink:ink)}
        return y+lines.count
    }
    static func durationMeter(_ c:inout TerminalCanvas,title:String,seconds:Double?,target:Double,x:Int,y:Int,w:Int,ink:TerminalInk) {
        let text=seconds.map{String(format:L10n.text("%.0f / %.0f s"),min($0,target),target)} ?? L10n.text("no evidence")
        c.write(TerminalText.clipped(title,to:max(1,w-18)),x:x,y:y,ink:ink)
        c.write(right(text,min(w,18)),x:x+max(0,w-18),y:y,ink:.secondary)
        meter(&c,seconds.map{$0/target},x:x,y:y+1,width:w,ink:ink)
    }
    static func processSeries(_ state:TerminalState,_ metric:(ProcessSample)->Double?)->[Double?] {
        guard let id=state.selectedProcess?.id else {return []}
        return values(recent(state)) { sample in sample.processes.first{$0.id==id}.flatMap(metric) }
    }
    static func miniResource(_ c:inout TerminalCanvas,title:String,value:String,series:[Double?],x:Int,y:Int,w:Int,ink:TerminalInk,scale:String,ceiling:Double?,dense:Bool=false) {
        section(&c,title,x:x,y:y,w:w,ink:ink)
        c.write(TerminalText.clipped(value,to:w),x:x,y:y+1,ink:ink)
        graph(&c,values:series,x:x,y:y+2,width:w,height:dense ? 1:3,ceiling:ceiling,ink:ink)
        c.write(TerminalText.clipped(scale,to:w),x:x,y:y+(dense ? 3:5),ink:.muted)
    }
    static func processResourceCharts(_ c:inout TerminalCanvas,_ state:TerminalState,x:Int,y:Int,w:Int,stacked:Bool,dense:Bool=false)->Int {
        guard let p=state.selectedProcess else {return y}
        let cpu=processSeries(state,{$0.cpuCores}),mem=processSeries(state,{$0.footprintBytes.map{Double($0)}})
        let cpuPeak=max(1,cpu.compactMap{$0}.max() ?? 1),memPeak=max(1,mem.compactMap{$0}.max() ?? 1)
        let signals=resourceSignals(cpuCores:p.cpuCores,footprintBytes:p.footprintBytes,memoryDeltaBytes:p.memoryDeltaBytes)
        let cw=stacked ? w:(w-2)/2
        miniResource(&c,title:"CPU",value:cores(p.cpuCores)+L10n.text(" cores"),series:cpu,x:x,y:y,w:cw,ink:resourceInk(signals,.cpu,normal:.cpu),scale:cpu.contains{$0 != nil} ? L10n.text("0–\(cores(cpuPeak)) cores · samples"):L10n.text("No measurements"),ceiling:cpuPeak,dense:dense)
        let chartHeight=dense ? 4:7
        let my=stacked ? y+chartHeight:y,mx=stacked ? x:x+cw+2,mw=stacked ? w:w-cw-2
        let memoryScale=mem.contains{$0 != nil} && memPeak<Double(UInt64.max) ? L10n.text("0–\(formatBytes(UInt64(memPeak))) · samples"):L10n.text("No measurements")
        miniResource(&c,title:L10n.text("FOOTPRINT"),value:formatBytes(p.footprintBytes)+"  Δ "+delta(p.memoryDeltaBytes),series:mem,x:mx,y:my,w:mw,ink:resourceInk(signals,.memory,normal:.memory),scale:memoryScale,ceiling:memPeak,dense:dense)
        return my+chartHeight
    }
    static func observationSection(_ c:inout TerminalCanvas,_ p:ProcessSample,_ a:ProcessAssessment,x:Int,y:Int,w:Int,dense:Bool=false)->Int {
        section(&c,L10n.text("OBSERVATION TIME · not a score"),x:x,y:y,w:w,ink:.cpu)
        durationMeter(&c,title:L10n.text("Sustained CPU ≥1 core"),seconds:a.highCPUSeconds,target:30,x:x,y:y+1,w:w,ink:.cpu)
        durationMeter(&c,title:L10n.text("Low activity"),seconds:a.quietSeconds,target:600,x:x,y:y+(dense ? 3:4),w:w,ink:a.quietObservationState == .qualified ? .warning:.good)
        var row=y+(dense ? 5:7)
        if dense {
            row=paragraph(&c,a.recommendations.first?.title ?? L10n.text("No recommendation · observing"),x:x,y:row,w:w,ink:a.recommendations.isEmpty ? .secondary:.warning)+1
        }
        let ageOK=p.ageSeconds.flatMap{$0.isFinite && $0>=0 ? $0>=7200:nil}
        let cpuOK=p.cpuCores.flatMap{$0.isFinite && $0>=0 ? $0<0.02:nil}
        let diskOK:Bool? = p.diskReadBytesPerSecond.flatMap{r in p.diskWriteBytesPerSecond.flatMap{r.isFinite && r>=0 && $0.isFinite && $0>=0 ? r<1024 && $0<1024:nil}}
        let memoryOK=p.footprintBytes.map{$0>=268_435_456}
        let checks:[(String,Bool?)]=[(L10n.text("Age ≥2 h"),ageOK),("CPU <0.02",cpuOK),(L10n.text("Disk <1 KiB/s"),diskOK),(L10n.text("Footprint ≥256 MiB"),memoryOK)]
        let col=(w-2)/2
        for (i,check) in checks.enumerated() {
            let mark=check.1 == true ? "✓":check.1 == false ? "·":"?"
            c.write(TerminalText.clipped(mark+" "+check.0,to:col),x:x+(i%2)*(col+2),y:row+i/2,ink:check.1 == true ? .good:.muted)
        }
        row+=3
        row=paragraph(&c,a.idleStatus,x:x,y:row,w:w,ink:.secondary)
        return row+1
    }
    static func recommendationSection(_ c:inout TerminalCanvas,_ a:ProcessAssessment,x:Int,y:Int,w:Int)->Int {
        let count=a.recommendations.count
        section(&c,count==0 ? L10n.text("ASSESSMENT · no recommendation"):L10n.text("ASSESSMENT · \(count) findings"),x:x,y:y,w:w,ink:count==0 ? .secondary:.warning)
        var row=y+1
        if count==0 {row=paragraph(&c,L10n.text("No termination recommendation now. Monitor usage and observation time."),x:x,y:row,w:w,ink:.muted)}
        for rec in a.recommendations {
            row=paragraph(&c,"◆ "+rec.title.uppercased(with:L10n.locale),x:x,y:row,w:w,ink:.warning)
            row=paragraph(&c,rec.evidence,x:x,y:row,w:w)
            row=paragraph(&c,rec.caveat,x:x,y:row,w:w,ink:.muted)+1
        }
        let actions=Array(Set(a.recommendations.map(\.action))).sorted()
        if !actions.isEmpty {
            section(&c,L10n.text("WHAT CAN I DO?"),x:x,y:row,w:w,ink:.good);row+=1
            for action in actions {row=paragraph(&c,action,x:x,y:row,w:w)+1}
        }
        return row+1
    }
    static func swapInk(_ assessment:SwapAssessment)->TerminalInk {
        switch assessment.activity {case .writing:return .warning;case .reading:return .disk;case .idle:return .good;case .unknown:return .muted}
    }
    static func swapContent(_ c:inout TerminalCanvas,_ state:TerminalState,x:Int,y:Int,w:Int,charts:Bool,brief:Bool=false)->Int {
        guard let s=state.visibleSnapshot else {return y}
        let history=recent(state),a=assessSwap(snapshot:s,history:state.visibleHistory)
        section(&c,L10n.text("SWAP · system-wide"),x:x,y:y,w:w,ink:.memory)
        var row=y+1
        row=paragraph(&c,a.title,x:x,y:row,w:w,ink:swapInk(a))
        c.write(TerminalText.clipped(L10n.text("Stored on disk  ")+formatBytes(s.swapUsedBytes),to:w),x:x,y:row,ink:.primary);row+=1
        if charts {
            let stocks=values(history,{$0.swapUsedBytes.map{Double($0)}}),peak=stocks.compactMap{$0}.max()
            let stockHeight=brief ? 2:3,rateHeight=brief ? 1:2
            graph(&c,values:stocks,x:x,y:row,width:w,height:stockHeight,ceiling:nil,ink:.memory);row+=stockHeight
            let scale=peak.flatMap{$0<Double(UInt64.max) ? UInt64($0):nil}.map{"0–"+formatBytes($0)} ?? L10n.text("no measurements")
            c.write(TerminalText.clipped(scale+L10n.text(" · stock"),to:w),x:x,y:row,ink:.muted);row+=brief ? 1:2
            let out=values(history,{$0.swapOutBytesPerSecond}),input=values(history,{$0.swapInBytesPerSecond})
            let ratePeak=max(1,(out+input).compactMap{$0}.max() ?? 1)
            c.write(TerminalText.clipped("RAM → disk  "+formatRate(s.swapOutBytesPerSecond),to:w),x:x,y:row,ink:.warning);row+=1
            graph(&c,values:out,x:x,y:row,width:w,height:rateHeight,ceiling:ratePeak,ink:.warning);row+=rateHeight+(brief ? 0:1)
            c.write(TerminalText.clipped("Disk → RAM  "+formatRate(s.swapInBytesPerSecond),to:w),x:x,y:row,ink:.disk);row+=1
            graph(&c,values:input,x:x,y:row,width:w,height:rateHeight,ceiling:ratePeak,ink:.disk);row+=rateHeight
            c.write(TerminalText.clipped(((out+input).contains{$0 != nil} ? "0–"+formatRate(ratePeak)+L10n.text(" · shared scale"):L10n.text("No transfer measurements")),to:w),x:x,y:row,ink:.muted);row+=brief ? 1:2
        } else {
            row=paragraph(&c,"RAM → disk "+formatRate(s.swapOutBytesPerSecond)+" · disk → RAM "+formatRate(s.swapInBytesPerSecond),x:x,y:row,w:w,ink:.disk)
        }
        if let change=a.stockDeltaBytes,let seconds=a.observedSeconds {
            row=paragraph(&c,L10n.text("\(Int(seconds)) s stock change  ")+delta(change),x:x,y:row,w:w,ink:change>0 ? .warning:.secondary)
        }
        let summary=brief ? L10n.text("Swap stock and transfers are separate. Reads do not imply an equal decrease in stock."):a.summary
        row=paragraph(&c,summary,x:x,y:row+1,w:w)
        section(&c,L10n.text("REDUCE PRESSURE"),x:x,y:row+1,w:w,ink:.good)
        let action=brief ? (a.shouldReviewMemory ? L10n.text("Save and normally close unneeded workloads; compare pressure and swap writes."):L10n.text("Monitor pressure and writes; do not close apps solely based on swap size.")):a.action
        row=paragraph(&c,action,x:x,y:row+2,w:w)
        row=paragraph(&c,brief ? L10n.text("Per-process swap and exact reclaimable amounts are unknown."):a.limitation,x:x,y:row+1,w:w,ink:.muted)
        return row+1
    }
    static func assessmentDocument(_ state:TerminalState,width:Int,compact:Bool,dense:Bool=false)->(TerminalCanvas,Int) {
        var doc=TerminalCanvas(width:width,height:300)
        guard let p=state.selectedProcess,let a=processAssessment(state) else {doc.write(L10n.text("No selected process"),x:0,y:0,ink:.muted);return(doc,1)}
        var y=paragraph(&doc,dense ? TerminalText.clipped(p.name,to:width):p.name,x:0,y:0,w:width,ink:.primary)
        let identity=L10n.text("PID \(p.pid) · Age \(age(p.ageSeconds)) · \(p.applicationName)")
        y=paragraph(&doc,dense ? TerminalText.clipped(identity,to:width):identity,x:0,y:y,w:width,ink:.muted)+(dense ? 0:1)
        if state.selectedProcessIsMissing {y=paragraph(&doc,L10n.text("PROCESS NO LONGER VISIBLE · last observed sample"),x:0,y:y,w:width,ink:.warning)+(dense ? 0:1)}
        else if state.frozen || state.historyVisible {y=paragraph(&doc,L10n.text("HISTORICAL SAMPLE · NOT A LIVE DECISION"),x:0,y:y,w:width,ink:.warning)+(dense ? 0:1)}
        let label=resourceSummary(p,a)
        y=paragraph(&doc,dense ? TerminalText.clipped(label,to:width):label,x:0,y:y,w:width,ink:a.signals.isEmpty ? .secondary:.warning)
        let next="→ "+quickAction(state,a)
        y=paragraph(&doc,dense ? TerminalText.clipped(next,to:width):next,x:0,y:y,w:width,ink:.good)+(dense ? 0:1)
        y=processResourceCharts(&doc,state,x:0,y:y,w:width,stacked:compact,dense:dense)
        let split = !compact && width>=110
        let leftWidth=split ? (width*3/5)-2:width
        let rightX=leftWidth+4,rightWidth=width-rightX
        let start=y
        y=observationSection(&doc,p,a,x:0,y:y,w:leftWidth,dense:dense)
        y=recommendationSection(&doc,a,x:0,y:y,w:leftWidth)
        if split {y=max(y,swapContent(&doc,state,x:rightX,y:start,w:rightWidth,charts:true))}
        else if !compact {y=swapContent(&doc,state,x:0,y:y,w:width,charts:false)}
        if !compact {
            section(&doc,L10n.text("MEASUREMENT CONTEXT"),x:0,y:y,w:width,ink:.muted);y+=1
            y=paragraph(&doc,L10n.text("Project: \(p.projectName ?? L10n.text("unknown")) · Identity \(p.id)"),x:0,y:y,w:width,ink:.muted)
            y=paragraph(&doc,L10n.text("Charts show samples from the last 120 s, each on its own scale. Footprint is not RAM percentage or reclaimable swap."),x:0,y:y,w:width,ink:.muted)
            y=paragraph(&doc,L10n.text("Thresholds: CPU ≥1 core / ≥2 red; footprint ≥2 GiB / ≥4 red; Δ ≥100 MiB. b: system memory/swap view."),x:0,y:y,w:width,ink:.muted)
        }
        return(doc,y)
    }
    static func swapInspector(_ c:inout TerminalCanvas,_ state:TerminalState,x:Int,y:Int,w:Int,h:Int) {
        c.box(x:x,y:y,width:w,height:h,title:L10n.text("SWAP / MEMORY · b back"),ink:.memory)
        var doc=TerminalCanvas(width:w-4,height:200)
        let height=swapContent(&doc,state,x:0,y:0,w:w-4,charts:h>=25,brief:h<44)
        c.copy(doc,toX:x+2,toY:y+1,rowCount:min(h-2,height))
        if height>h-2 {c.write(L10n.text(" Enter: process and swap context "),x:x+2,y:y+h-1,ink:.cpu)}
    }
    static func swapBand(_ c:inout TerminalCanvas,_ state:TerminalState,y:Int,w:Int,h:Int) {
        guard let s=state.visibleSnapshot else {return}
        let a=assessSwap(snapshot:s,history:state.visibleHistory),history=recent(state)
        c.box(x:0,y:y,width:w,height:h,title:L10n.text("SWAP / MEMORY · b back"),ink:.memory)
        let half=w/2
        c.write(TerminalText.clipped(a.title,to:w-4),x:2,y:y+1,ink:swapInk(a))
        c.write(TerminalText.clipped(L10n.text("Stock ")+formatBytes(s.swapUsedBytes),to:half-4),x:2,y:y+2,ink:.memory)
        let stocks=values(history,{$0.swapUsedBytes.map{Double($0)}}),out=values(history,{$0.swapOutBytesPerSecond}),input=values(history,{$0.swapInBytesPerSecond})
        let peak=stocks.compactMap{$0}.max(),ratePeak=max(1,(out+input).compactMap{$0}.max() ?? 1)
        c.write(TerminalText.clipped("RAM→disk "+formatRate(s.swapOutBytesPerSecond),to:half-3),x:half,y:y+2,ink:.warning)
        graph(&c,values:stocks,x:2,y:y+3,width:half-4,height:2,ceiling:nil,ink:.memory)
        c.write(TerminalPlot.sparkline(out,width:w-half-2,ceiling:ratePeak),x:half,y:y+3,ink:.warning)
        c.write(TerminalText.clipped("Disk→RAM "+formatRate(s.swapInBytesPerSecond),to:half-3),x:half,y:y+4,ink:.disk)
        let stockScale=peak.flatMap{$0<Double(UInt64.max) ? UInt64($0):nil}.map{"0–"+formatBytes($0)+L10n.text(" · stock")} ?? L10n.text("No stock measurements")
        c.write(TerminalText.clipped(stockScale,to:half-4),x:2,y:y+5,ink:.muted)
        let rateScale=(out+input).contains{$0 != nil} ? "0–"+formatRate(ratePeak)+L10n.text(" · rate"):L10n.text("No rate measurements")
        c.write(TerminalText.clipped(rateScale,to:w-half-2),x:half,y:y+5,ink:.muted)
        c.write(TerminalText.clipped(L10n.text("Footprint order · exact swap ownership/reclaimable amount unknown"),to:w-4),x:2,y:y+6,ink:.secondary)
    }
}
