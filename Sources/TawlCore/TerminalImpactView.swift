import Foundation

/// Equal-duration chart cells. Uncollected future is distinct from an observed gap.
enum ImpactChartCell { case future, missing, value(Double) }
enum ImpactChartMetric { case cpu, pressure, stock, writes }

extension TerminalRenderer {
    static func impactCells(_ impact:ClosureImpact,width:Int,metric:ImpactChartMetric)->[ImpactChartCell] {
        guard width>0 else {return []}
        let start=impact.startedAt-30, now=impact.startedAt+impact.elapsed, step=90/Double(width)
        let intervals = metric == .cpu || metric == .writes
        var segments:[(Double,Double,Double?)]=[]
        for (points,end) in [(impact.before,impact.startedAt),(impact.after,now)] {
            for (i,p) in points.enumerated() {
                let value:Double?
                switch metric {
                case .cpu:value=p.cpuPercent
                case .writes:value=p.swapOutBytesPerSecond
                case .stock:value=p.swapUsedBytes.map{Double($0)}
                case .pressure:
                    switch p.pressure {case .normal:value=1;case .warning:value=2;case .critical:value=3;case .unknown:value=nil}
                }
                if intervals {
                    if let duration=p.intervalSeconds { segments.append((max(start,p.time-duration),p.time,value)) }
                } else {
                    let until=min(end,min(p.time+ClosureImpact.maximumInterval,i+1<points.count ? points[i+1].time:end))
                    if until>p.time {segments.append((max(start,p.time),until,value))}
                }
            }
        }
        return (0..<width).map { column in
            let lo=start+Double(column)*step, hi=min(now,lo+step)
            if lo>=now {return .future}
            var coverage=0.0, weighted=0.0, peak=0.0
            for (a,b,value) in segments {
                let overlap=max(0,min(hi,b)-max(lo,a))
                guard overlap>0,let value,value.isFinite,value>=0 else {continue}
                let total=coverage+overlap
                weighted += (value-weighted)*(overlap/total)
                coverage=total;peak=max(peak,value)
            }
            // A column with a meaningful gap remains unknown; do not bridge pauses.
            guard coverage>0,coverage>=max(0,hi-lo)-0.001 else {return .missing}
            return .value(metric == .pressure ? peak:weighted)
        }
    }
    static func impactPlot(_ c:inout TerminalCanvas,_ cells:[ImpactChartCell],x:Int,y:Int,h:Int,
                           low:Double=0,high:Double,ink:TerminalInk,pressure:Bool=false) {
        let glyphs=Array(" ▁▂▃▄▅▆▇█"), span=max(0.000001,high-low)
        let marker=cells.count/3
        for (column,cell) in cells.enumerated() {
            if column==marker {
                for row in 0..<h {c.write("│",x:x+column,y:y+row,ink:.secondary)}
                continue
            }
            switch cell {
            case .future: break
            case .missing: c.write("·",x:x+column,y:y+h-1,ink:.muted)
            case .value(let value):
                let colour:TerminalInk=pressure ? (value>=3 ? .danger:value>=2 ? .warning:.good):ink
                let fraction=max(0,min(1,(value-low)/span))
                for row in 0..<h {
                    let units=fraction*Double(h)*8-Double(h-row-1)*8
                    let level=Int(max(0,min(8,units)).rounded(.up))
                    if level>0 {c.write(String(glyphs[level]),x:x+column,y:y+row,ink:colour)}
                    else if row==h-1 {c.write("─",x:x+column,y:y+row,ink:colour)}
                }
            }
        }
    }
    static func impactPercent(_ value:Double?)->String { value.map{String(format:"%.1f%%",$0)} ?? "—" }
    static func impactPointDelta(_ value:Double?)->String {
        guard let value else {return "—"}
        return (value<0 ? "−":value>0 ? "+":"")+String(format:L10n.text("%.1f points"),abs(value))
    }
    static func impactPressure(_ value:Pressure)->String {
        switch value {case .normal:return "Normal";case .warning:return L10n.text("Warning");case .critical:return L10n.text("Critical");case .unknown:return L10n.text("Unknown")}
    }
    static func impactCoverage(_ before:Double,_ after:Double,_ elapsed:Double)->String {
        String(format:L10n.text("Valid time: %.0f/30 s → %.0f/%.0f s"),before,after,elapsed)
    }
    static func impactBytes(_ value:Double)->String {
        guard value.isFinite,value>=0,value<Double(UInt64.max) else {return "—"}
        return formatBytes(UInt64(value))
    }
    static func impactView(_ c:inout TerminalCanvas,_ state:TerminalState) {
        guard let report=state.closureImpact else {return}
        let s=report.summary,w=c.width,inner=w-4
        let status=state.impactSession?.status ?? .unverified
        var outcome=closureOutcome(status)
        if report.isComplete {
            if status == .stillRunning {outcome.0=L10n.text("RUNNING AT LAST CHECK")}
            else if status == .waitingForExit {outcome.0=L10n.text("EXIT NOT OBSERVED")}
        }
        c.fillRow(y:0,fill:.panel)
        c.write(L10n.text(" TAWL / LAST TERMINATION · SYSTEM COMPARISON"),x:0,y:0,ink:.cpu)
        let identity=L10n.text("PID \(report.intent.pid) · Request \(time(report.startedOn))")
        let identityX=w-1-TerminalText.width(identity)
        c.write(TerminalText.clipped(report.intent.applicationName,to:max(1,identityX-3)),x:1,y:1,ink:.primary)
        c.write(identity,x:identityX,y:1,ink:.secondary)
        c.write(TerminalText.clipped(outcome.0+" · "+(report.isComplete ? L10n.text("Measurement complete"):L10n.text("Observing")),to:w-2),x:1,y:2,ink:outcome.2)
        let elapsed=String(format:"%.0f",report.elapsed)
        c.write(TerminalText.clipped(L10n.text("Before 30 s  →  After \(elapsed) / 60 s · ")+(report.isComplete ? L10n.text("Final result"):L10n.text("Partial comparison")),to:w-2),x:1,y:3,ink:.secondary)
        let marker=2+inner/3
        c.write(L10n.text("−30 s"),x:2,y:4,ink:.muted)
        c.write(L10n.text("0 · REQUEST"),x:max(2,marker-4),y:4,ink:.primary)
        c.write(L10n.text("+60 s"),x:w-8,y:4,ink:.muted)
        let available=c.height-8,base=available/4,remainder=available%4
        var y=5
        let stocks=(report.before+report.after).compactMap{$0.swapUsedBytes.map{Double($0)}}
        let minStock=stocks.min() ?? 0,maxStock=stocks.max() ?? 0
        let margin=max(67_108_864,(maxStock-minStock)*0.1)
        let stockLow=max(0,minStock-margin),stockHigh=maxStock+margin
        let writes=(report.before+report.after).compactMap(\.swapOutBytesPerSecond)
        let writeHigh=max(1,writes.max() ?? 1)
        let coverageCPU=impactCoverage(s.before.cpu.coverageSeconds,s.after.cpu.coverageSeconds,report.elapsed)
        let coverageWrite=impactCoverage(s.before.swapOut.coverageSeconds,s.after.swapOut.coverageSeconds,report.elapsed)
        let descriptors:[(String,String,String,ImpactChartMetric,TerminalInk,Double,Double)]=[
            (L10n.text("SYSTEM CPU"), "\(impactPercent(s.before.cpu.value)) → \(impactPercent(s.after.cpu.value))  Δ \(impactPointDelta(s.cpuDeltaPercentagePoints))", coverageCPU+L10n.text(" · avg. · 0–100%"), .cpu,.cpu,0,100),
            (L10n.text("MEMORY PRESSURE"), "\(impactPressure(s.before.pressure)) → \(impactPressure(s.after.pressure))", L10n.text("Last state · ▁ Normal  ▄ Warning  █ Critical · no numeric average"), .pressure,.memory,0,3),
            (L10n.text("SWAP STOCK"), "\(formatBytes(s.before.swapUsedBytes)) → \(formatBytes(s.after.swapUsedBytes))  Δ \(delta(s.swapUsedDeltaBytes))", L10n.text("Last value · scale \(impactBytes(stockLow))–\(impactBytes(stockHigh)) · zoomed"), .stock,.memory,stockLow,stockHigh),
            (L10n.text("SWAP WRITES"), "\(formatRate(s.before.swapOut.value)) → \(formatRate(s.after.swapOut.value))", coverageWrite+" · RAM→disk · 0–\(formatRate(writeHigh))", .writes,.disk,0,writeHigh)
        ]
        for (index,item) in descriptors.enumerated() {
            let height=base+(index<remainder ? 1:0),graphHeight=max(1,height-2)
            c.fillRow(y:y,from:1,to:w-1,fill:.panel)
            c.write(item.0,x:2,y:y,ink:item.4)
            let summaryWidth=TerminalText.width(item.1)
            let summaryX=max(2+TerminalText.width(item.0)+2,w-2-summaryWidth)
            c.write(TerminalText.clipped(item.1,to:w-2-summaryX),x:summaryX,y:y,ink:item.4)
            impactPlot(&c,impactCells(report,width:inner,metric:item.3),x:2,y:y+1,h:graphHeight,
                       low:item.5,high:item.6,ink:item.4,pressure:item.3 == .pressure)
            c.write(TerminalText.clipped(item.2,to:inner),x:2,y:y+height-1,ink:.muted)
            y+=height
        }
        c.write(TerminalText.clipped(L10n.text("· no sample  blank: future · Change alone does not prove causation."),to:w-2),x:1,y:c.height-3,ink:.muted)
        c.write(TerminalText.clipped(L10n.text("CPU/writes: time-weighted avg. · Stock change is not exact reclaimed RAM."),to:w-2),x:1,y:c.height-2,ink:.muted)
        c.fillRow(y:c.height-1,fill:.panel)
        c.write(L10n.text(" d: save HTML report · Esc / Enter back · e last report · q quit"),x:0,y:c.height-1,ink:.secondary)
    }
}
