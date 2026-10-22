import Foundation

/// Bounds hardware detail so the application comparison remains usable below it.
struct HardwareLayout {
    let compact: Bool
    let panelHeight: Int
    let cpuWidth: Int
    let columns: Int
    let cellHeight: Int
    let cpuCapacity: Int
    let gpuCapacity: Int
    let pages: Int
    init(snapshot: Snapshot, width: Int, height: Int) {
        compact = width < 120 || height < 32
        let count = max(1,snapshot.cpuCores?.count ?? 0)
        if compact {
            cpuWidth = width
            columns = width >= 96 ? 4 : 3
            cellHeight = height >= 30 ? 2 : 1
            let budget = max(8,min(18,height-16))
            let rows = max(1,min((count+columns-1)/columns,(budget-4)/cellHeight))
            panelHeight = rows*cellHeight+4
            cpuCapacity = rows*columns; gpuCapacity = 1
        } else {
            cpuWidth = width-max(38,width/3)
            columns = max(2,(cpuWidth-4)/26)
            cellHeight = height >= 50 ? 4 : 3
            let budget = max(8,min(22,height-28))
            let rows = max(1,min((count+columns-1)/columns,(budget-2)/cellHeight))
            panelHeight = max(8,rows*cellHeight+2)
            cpuCapacity = rows*columns
            gpuCapacity = max(1,(panelHeight-3)/5)
        }
        let cpuPages = (count+cpuCapacity-1)/cpuCapacity
        let gpuPages = (max(1,snapshot.gpus?.count ?? 0)+gpuCapacity-1)/gpuCapacity
        pages = max(1,max(cpuPages,gpuPages))
    }
}

extension TerminalRenderer {
    static func utilization(_ value:Double?)->String {
        guard let value,value.isFinite,value>=0,value<=100 else {return "—"}
        return String(format:"%.1f%%",value)
    }
    static func hardwareInk(_ value:Double?,normal:TerminalInk)->TerminalInk {
        guard let value,value.isFinite else {return .muted}
        return value>=95 ? .danger:value>=80 ? .warning:normal
    }
    static func coreKind(_ kind:CPUCoreKind)->String {
        switch kind {case .efficiency:return "E";case .performance:return "P";case .unknown:return "?"}
    }
    static func hardwarePanel(_ c:inout TerminalCanvas,_ state:TerminalState,_ s:Snapshot,_ history:[Snapshot],y:Int)->Int {
        let l=HardwareLayout(snapshot:s,width:c.width,height:c.height)
        let page=min(max(0,state.hardwarePage),l.pages-1)
        let cores=(s.cpuCores ?? []).sorted{$0.id<$1.id}
        let cp=max(1,(cores.count+l.cpuCapacity-1)/l.cpuCapacity)
        let start=(page % cp)*l.cpuCapacity
        let shown=Array(cores.dropFirst(start).prefix(l.cpuCapacity))
        let pages=l.pages>1 ? " · \(page+1)/\(l.pages) [ ]":""
        let cpuTitle="CPU · \(cores.count)/\(s.logicalCPUCount) çek. · 0–100%"+pages
        c.box(x:0,y:y,width:l.cpuWidth,height:l.panelHeight,title:cpuTitle,ink:.border)
        c.write(TerminalText.clipped(cpuTitle,to:l.cpuWidth-4),x:2,y:y,ink:.cpu)
        let cellWidth=(l.cpuWidth-4)/l.columns
        for (i,core) in shown.enumerated() {
            let x=2+(i%l.columns)*cellWidth,cy=y+1+(i/l.columns)*l.cellHeight
            let name=String(format:"%02d",core.id+1)+coreKind(core.kind)
            let ink=hardwareInk(core.utilizationPercent,normal:.cpu)
            let series=values(history){ $0.cpuCores?.first{$0.id==core.id && $0.kind==core.kind}?.utilizationPercent }
            if l.cellHeight==1 {
                c.write(name,x:x,y:cy,ink:.secondary)
                let gw=max(1,cellWidth-12)
                c.write(TerminalPlot.sparkline(series,width:gw,ceiling:100),x:x+4,y:cy,ink:ink)
                c.write(right(utilization(core.utilizationPercent),7),x:x+cellWidth-8,y:cy,ink:ink)
            } else {
                c.write("CPU "+name,x:x,y:cy,ink:.secondary)
                c.write(right(utilization(core.utilizationPercent),7),x:x+cellWidth-8,y:cy,ink:ink)
                graph(&c,values:series,x:x,y:cy+1,width:cellWidth-2,height:l.cellHeight-1,ceiling:100,ink:ink)
            }
        }
        if cores.isEmpty {
            c.write("Çekirdek ölçümü yok · eski kayıt veya okunamadı",x:2,y:y+1,ink:.muted)
        }
        let gpuList=s.gpus ?? []
        let gp=max(1,(gpuList.count+l.gpuCapacity-1)/l.gpuCapacity)
        let gpuStart=(page % gp)*l.gpuCapacity
        if l.compact {
            let gy=y+l.panelHeight-3
            if let gpu=gpuList.dropFirst(gpuStart).first {
                let identity=(gpuList.count>1 ? "GPU \(gpuStart+1)/\(gpuList.count) · ":"GPU · ")+gpu.name+(gpu.coreCount.map{" · \($0) çek."} ?? "")
                let metric=utilization(gpu.utilizationPercent)+" · aygıt toplamı"
                c.write(TerminalText.clipped(identity,to:c.width-30),x:2,y:gy,ink:.gpu)
                c.write(right(metric,27),x:c.width-29,y:gy,ink:hardwareInk(gpu.utilizationPercent,normal:.gpu))
                let gw=max(8,c.width/2-4)
                graph(&c,values:values(history){$0.gpus?.first{$0.id==gpu.id}?.utilizationPercent},x:2,y:gy+1,width:gw,height:1,ceiling:100,ink:.gpu)
                c.write("GPU çekirdek ölçümü yok",x:gw+4,y:gy+1,ink:.muted)
            } else {
                c.write("GPU · ölçüm yok",x:2,y:gy,ink:.muted)
                c.write("Çekirdek bazında GPU kullanımı sunulmuyor.",x:2,y:gy+1,ink:.muted)
            }
            c.write(" E verim · P performans · ? tür bilinmiyor ",x:2,y:y+l.panelHeight-1,ink:.muted)
        } else {
            let gx=l.cpuWidth,gw=c.width-gx
            c.box(x:gx,y:y,width:gw,height:l.panelHeight,title:"GPU · AYGIT TOPLAMI · 0–100%",ink:.border)
            c.write("GPU · AYGIT TOPLAMI · 0–100%",x:gx+2,y:y,ink:.gpu)
            let devices=Array(gpuList.dropFirst(gpuStart).prefix(l.gpuCapacity))
            let deviceHeight=max(5,(l.panelHeight-3)/max(1,devices.count))
            for (i,gpu) in devices.enumerated() {
                let gy=y+1+i*deviceHeight
                let name=(gpuList.count>1 ? "GPU \(gpuStart+i+1)/\(gpuList.count) · ":"")+gpu.name
                c.write(TerminalText.clipped(name,to:gw-4),x:gx+2,y:gy,ink:.secondary)
                c.write(gpu.coreCount.map{"\($0) GPU çekirdeği"} ?? "Çekirdek sayısı bilinmiyor",x:gx+2,y:gy+1,ink:.muted)
                c.write(right(utilization(gpu.utilizationPercent),7),x:gx+gw-9,y:gy+1,ink:hardwareInk(gpu.utilizationPercent,normal:.gpu))
                graph(&c,values:values(history){$0.gpus?.first{$0.id==gpu.id}?.utilizationPercent},x:gx+2,y:gy+2,width:gw-4,height:deviceHeight-2,ceiling:100,ink:.gpu)
            }
            if devices.isEmpty {c.write("GPU ölçümü okunamadı",x:gx+2,y:y+2,ink:.muted)}
            c.write("Çekirdek bazında kullanım sunulmuyor",x:gx+2,y:y+l.panelHeight-2,ink:.muted)
            let high=cores.filter{($0.utilizationPercent ?? -1)>=80}.count
            let known=cores.filter{$0.utilizationPercent != nil}.count
            let legend=" E verim · P performans · ≥80%: \(high)/\(known) ölçülen "
            c.write(TerminalText.clipped(legend,to:l.cpuWidth-4),x:2,y:y+l.panelHeight-1,ink:.muted)
        }
        let pressure = s.pressure == .normal ? "NORMAL" : s.pressure == .warning ? "BASKI VAR" : s.pressure == .critical ? "KRİTİK" : "?"
        let health="BELLEK \(pressure) · Swap \(formatBytes(s.swapUsedBytes)) · Disk ↓\(formatRate(s.diskReadBytesPerSecond)) · Ağ ↓\(formatRate(s.networkInBytesPerSecond))"
        c.write(TerminalText.clipped(health,to:c.width-2),x:1,y:y+l.panelHeight,ink:pressureInk(s.pressure))
        return y+l.panelHeight+1
    }
}
