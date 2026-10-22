import Foundation
import AppKit

extension TerminalState {
    public mutating func exportImpact(directory:URL = URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("raporlar",isDirectory:true)) {
        impactExportVisible=true;impactExportURL=nil;impactExportError=""
        guard let impact=closureImpact else {
            impactExportError="Dışa aktarılacak karşılaştırma yok. Önce onaylı bir kapatma isteği gönder.";return
        }
        do {
            impactExportURL=try ClosureImpactExporter.write(impact:impact,status:impactSession?.status ?? .unverified,directory:directory)
        } catch {impactExportError="Rapor kaydedilemedi: "+error.localizedDescription+" Hedef: "+directory.path}
    }
    public mutating func openExportedImpact() {
        guard let url=impactExportURL else{return}
        if !NSWorkspace.shared.open(url) {impactExportError="Tarayıcı açılamadı. Kaydedilen dosyayı aşağıdaki yoldan açabilirsin."}
    }
}

extension TerminalRenderer {
    static func impactExportView(_ c:inout TerminalCanvas,_ state:TerminalState) {
        let w=min(c.width-4,106),h=min(c.height-4,20),x=(c.width-w)/2,y=2,inner=w-4
        let success=state.impactExportURL != nil,ink:TerminalInk=success ? .good:.warning
        c.fillRow(y:0,fill:.panel);c.write(" TAWL / RAPOR DIŞA AKTAR",x:0,y:0,ink:.cpu)
        c.box(x:x,y:y,width:w,height:h,title:success ? "HTML RAPOR KAYDEDİLDİ":"RAPOR KAYDEDİLEMEDİ",ink:ink)
        var row=y+2
        func lines(_ value:String)->[String] {TerminalText.wrapped(value,to:inner)}
        if let url=state.impactExportURL {
            c.write("Grafikler + süreç + uygulama + önce/sonra değerleri",x:x+2,y:row,ink:.primary);row+=2
            c.write("DOSYA",x:x+2,y:row,ink:.cpu);row+=1
            for line in lines(url.path).prefix(h-10) {c.write(line,x:x+2,y:row,ink:.primary);row+=1}
            row+=1
            c.write("Tek HTML dosyası · çevrimdışı açılır · mevcut dosyaya yazılmaz",x:x+2,y:row,ink:.muted)
        }
        if !state.impactExportError.isEmpty {
            for line in lines(state.impactExportError).prefix(max(1,y+h-4-row)) {c.write(line,x:x+2,y:row,ink:.warning);row+=1}
        }
        c.write(success ? "a: tarayıcıda aç · Esc / Enter: karşılaştırmaya dön":"Esc / Enter: karşılaştırmaya dön · d ile yeniden dene",x:x+2,y:y+h-3,ink:.cpu)
        c.write(success ? "Dosya kaydedildiği anı içerir; canlı ölçüm arka planda sürer.":"Karşılaştırma korunuyor; yazılabilir bir dizinden çalıştır.",x:x+2,y:y+h-2,ink:.muted)
        c.fillRow(y:c.height-1,fill:.panel)
        c.write(" Esc / Enter geri · "+(success ? "a raporu aç · ":"d yeniden dene · ")+"q çıkış",x:0,y:c.height-1,ink:.secondary)
    }
}
