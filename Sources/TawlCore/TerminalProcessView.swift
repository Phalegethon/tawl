import Foundation

extension TerminalRenderer {
    static func sortTitle(_ state:TerminalState)->String {
        (state.sort == .automatic ? "Oto ":"")+state.effectiveSort.title+state.sortDirection.symbol
    }
    static func sortHeader(_ label:String,_ key:WorkloadSort,_ state:TerminalState)->String {
        label+(state.effectiveSort == key ? state.sortDirection.symbol:"")
    }
    static func resourceInk(_ signals:[ResourceSignal],_ kind:ResourceKind,normal:TerminalInk)->TerminalInk {
        guard let value=signals.first(where:{$0.resource==kind}) else {return normal}
        return value.severity == .critical ? .danger:.warning
    }
    static func signalLabel(_ signals:[ResourceSignal])->String {
        let values=signals.map { signal in signal.resource == .cpu ? "CPU":signal.resource == .memory ? "RAM":"Δ" }
        return values.isEmpty ? "":values.joined(separator:"+")+"!"
    }
    static func resourceName(_ c:inout TerminalCanvas,name:String,signals:[ResourceSignal],selected:Bool,x:Int,y:Int,width:Int,reviewTag:String?=nil) {
        let tag=reviewTag ?? signalLabel(signals),reserve=tag.isEmpty ? 0:TerminalText.width(tag)+1
        c.write(TerminalText.clipped((selected ? "› ":"  ")+name,to:width-reserve),x:x,y:y,ink:selected ? .primary:.secondary)
        if !tag.isEmpty {c.write(tag,x:x+width-TerminalText.width(tag),y:y,ink:signals.contains{$0.severity == .critical} ? .danger:.warning)}
    }
    static func age(_ seconds:Double?)->String {
        guard let s=seconds,s.isFinite,s>=0,s<Double(Int.max) else {return "—"}
        if s>=86400 {return "\(Int(s/86400))g \(Int(s.truncatingRemainder(dividingBy:86400)/3600))sa"}
        if s>=3600 {return "\(Int(s/3600))sa \(Int(s.truncatingRemainder(dividingBy:3600)/60))dk"}
        return "\(Int(s/60))dk"
    }
    static func processAssessment(_ state:TerminalState)->ProcessAssessment? {
        guard let process=state.selectedProcess else {return nil}
        return state.assessment(for:process)
    }
    static func processInspector(_ c:inout TerminalCanvas,_ state:TerminalState,x:Int,y:Int,w:Int,h:Int) {
        c.box(x:x,y:y,width:w,height:h,title:"SEÇİLİ SÜREÇ · Enter değerlendirme",ink:.border)
        guard let process=state.selectedProcess,let assessment=processAssessment(state) else {
            c.write("Bir süreç seçin",x:x+2,y:y+1,ink:.muted);return
        }
        let inner=w-4
        if h<=8 {
            c.write(TerminalText.clipped("PID \(process.pid) · "+process.name,to:inner),x:x+2,y:y+1,ink:.primary)
            let plotWidth=max(8,inner-27)
            c.write(TerminalText.clipped("CPU "+cores(process.cpuCores)+" çek.",to:25),x:x+2,y:y+2,ink:.cpu)
            c.write(TerminalPlot.sparkline(processSeries(state,{$0.cpuCores}),width:plotWidth,ceiling:nil),x:x+28,y:y+2,ink:.cpu)
            c.write(TerminalText.clipped("Ayak izi "+formatBytes(process.footprintBytes),to:25),x:x+2,y:y+3,ink:.memory)
            c.write(TerminalPlot.sparkline(processSeries(state,{$0.footprintBytes.map{Double($0)}}),width:plotWidth,ceiling:nil),x:x+28,y:y+3,ink:.memory)
            let label=assessment.quietSeconds.map{"Düşük etkinlik \(Int($0))/600 sn"} ?? "Düşük etkinlik: kanıt yok"
            c.write(TerminalText.clipped(label,to:32),x:x+2,y:y+4,ink:.secondary)
            meter(&c,assessment.quietSeconds.map{$0/600},x:x+35,y:y+4,width:max(1,inner-33),ink:.good)
            let status=state.selectedProcessIsMissing ? "Süreç artık görünmüyor":state.frozen || state.historyVisible ? "GEÇMİŞ · canlı karar değil":assessment.recommendations.first?.title ?? "Öneri yok · Enter: değerlendirme"
            c.write(TerminalText.clipped(status,to:inner),x:x+2,y:y+5,ink:.warning)
            return
        }
        let (document,count)=assessmentDocument(state,width:inner,compact:true)
        c.copy(document,toX:x+2,toY:y+1,rowCount:min(h-2,count))
        if count>h-2 {c.write(TerminalText.clipped(" Enter: grafikler, kanıt ve öneri ",to:inner),x:x+2,y:y+h-1,ink:.cpu)}
    }
    static func processView(_ c:inout TerminalCanvas,_ state:TerminalState,bodyY:Int,bottom:Int)->(ids:[String],limit:Int) {
        let w=c.width,h=bottom-bodyY
        if state.processInfoVisible {
            c.box(x:0,y:bodyY,width:w,height:h,title:"DEĞERLENDİRME · Esc süreçlere dön",ink:.cpu)
            let (document,count)=assessmentDocument(state,width:w-4,compact:false,dense:h<=30)
            let capacity=max(1,h-2),limit=max(0,count-capacity),offset=min(state.detailScroll,limit)
            c.copy(document,fromRow:offset,toX:2,toY:bodyY+1,rowCount:capacity)
            c.write(" \(offset+1)–\(min(count,offset+capacity))/\(count) · ↑↓ ",x:max(2,w-27),y:bottom-1,ink:.muted)
            return ([],limit)
        }
        let side=w>=120 ? min(54,max(42,w/3)):0
        let tableWidth=w-side,tableBottom=side>0 ? bottom:bottom-7
        let members=state.visibleProcesses
        let selected=state.selectedWorkload
        let title=(state.recommendationsOnly ? "ÖNERİLER · ":"AYRINTI · ")+(selected?.name ?? "Seçili iş yok")
        c.box(x:0,y:bodyY,width:tableWidth,height:tableBottom-bodyY,title:title,ink:.cpu)
        let cpu=cores(selected?.cpuCores)+((selected?.unknownCPUCount ?? 0)>0 ? "*":"")
        let mem=(selected?.footprintBytes.map{formatBytes($0)} ?? "bilinmiyor")+((selected?.unknownMemoryCount ?? 0)>0 ? "*":"")
        c.write(TerminalText.clipped("\(members.count)/\(state.selectedMembers.count) süreç · Grup CPU \(cpu) çek. · Ayak izi \(mem)",to:tableWidth-4),x:2,y:bodyY+1,ink:.secondary)
        let allSignals=members.map{resourceSignals(cpuCores:$0.cpuCores,footprintBytes:$0.footprintBytes,memoryDeltaBytes:$0.memoryDeltaBytes)}
        let cpuCount=allSignals.filter{$0.contains{$0.resource == .cpu}}.count
        let memCount=allSignals.filter{$0.contains{$0.resource == .memory}}.count
        let growthCount=allSignals.filter{$0.contains{$0.resource == .growth}}.count
        c.write(TerminalText.clipped("\(sortTitle(state)) · Yüksek: CPU \(cpuCount) / RAM \(memCount) / Δ \(growthCount)",to:tableWidth-4),x:2,y:bodyY+2,ink:cpuCount+memCount+growthCount>0 ? .warning:.muted)
        let headerY=bodyY+3,firstY=headerY+1,capacity=max(1,tableBottom-firstY-1)
        let showAge=tableWidth>=92
        let ageWidth=showAge ? 11:0
        let nameWidth=tableWidth-4-7-9-12-12-ageWidth
        let nameX=9,cpuX=nameX+nameWidth,memX=cpuX+9,deltaX=memX+12,ageX=deltaX+12
        c.fillRow(y:headerY,from:1,to:tableWidth-1,fill:.panel)
        c.write("PID",x:2,y:headerY,ink:.muted)
        c.write(sortHeader("1 SÜREÇ",.name,state),x:nameX,y:headerY,ink:.secondary)
        c.write(right(sortHeader("2 CPU",.cpu,state),8),x:cpuX,y:headerY,ink:.cpu)
        c.write(right(sortHeader("3 AYAK İZİ",.footprint,state),11),x:memX,y:headerY,ink:.memory)
        c.write(right(sortHeader("4 Δ BELLEK",.memoryDelta,state),11),x:deltaX,y:headerY,ink:.muted)
        if showAge {c.write(right("AÇIK",10),x:ageX,y:headerY,ink:.muted)}
        let selectedID=state.selectedProcess?.id
        let index=members.firstIndex{$0.id==selectedID} ?? 0
        let start=min(max(0,index-capacity+1),max(0,members.count-capacity))
        var ids:[String]=[]
        for (i,process) in members.dropFirst(start).prefix(capacity).enumerated() {
            let y=firstY+i,selected=process.id==selectedID
            if selected {c.fillRow(y:y,from:1,to:tableWidth-1,fill:.selected)}
            let signals=resourceSignals(cpuCores:process.cpuCores,footprintBytes:process.footprintBytes,memoryDeltaBytes:process.memoryDeltaBytes)
            c.write(right(String(process.pid),6),x:1,y:y,ink:selected ? .primary:.muted)
            let quiet=state.recommendationsOnly && state.assessment(for:process).recommendations.contains{$0.kind == .quietMemory}
            resourceName(&c,name:process.name,signals:signals,selected:selected,x:nameX,y:y,width:nameWidth,reviewTag:quiet ? "AZ ETK.":nil)
            c.write(right(cores(process.cpuCores),8),x:cpuX,y:y,ink:resourceInk(signals,.cpu,normal:.cpu))
            c.write(right(formatBytes(process.footprintBytes),11),x:memX,y:y,ink:resourceInk(signals,.memory,normal:.primary))
            c.write(right(delta(process.memoryDeltaBytes),11),x:deltaX,y:y,ink:resourceInk(signals,.growth,normal:.muted))
            if showAge {c.write(right(age(process.ageSeconds),10),x:ageX,y:y,ink:.muted)}
            ids.append(process.id)
        }
        if members.isEmpty {
            let message=state.recommendationsOnly ? "Öneri adayı yok. o: tüm süreçler · gözlem sürüyor.":"Bu grupta görünür süreç yok."
            c.write(TerminalText.clipped(message,to:tableWidth-4),x:2,y:firstY,ink:.muted)
        }
        c.write(" \(members.isEmpty ? 0:start+1)–\(min(start+capacity,members.count))/\(members.count) süreç ",x:max(2,tableWidth-25),y:tableBottom-1,ink:.muted)
        if side>0 {processInspector(&c,state,x:tableWidth,y:bodyY,w:side,h:h)}
        else {processInspector(&c,state,x:0,y:tableBottom,w:w,h:7)}
        return (ids,0)
    }
}
