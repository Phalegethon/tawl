import Foundation
import AppKit

extension TerminalState {
    public mutating func exportImpact(directory:URL = URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("reports",isDirectory:true)) {
        impactExportVisible=true;impactExportURL=nil;impactExportError=""
        guard let impact=closureImpact else {
            impactExportError=L10n.text("No comparison to export. Send a confirmed termination request first.");return
        }
        do {
            impactExportURL=try ClosureImpactExporter.write(impact:impact,status:impactSession?.status ?? .unverified,directory:directory)
        } catch {impactExportError=L10n.text("Could not save report: ")+error.localizedDescription+L10n.text(" Destination: ")+directory.path}
    }
    public mutating func openExportedImpact() {
        guard let url=impactExportURL else{return}
        if !NSWorkspace.shared.open(url) {impactExportError=L10n.text("Could not open browser. Open the saved file at the path below.")}
    }
}

extension TerminalRenderer {
    static func impactExportView(_ c:inout TerminalCanvas,_ state:TerminalState) {
        let w=min(c.width-4,106),h=min(c.height-4,20),x=(c.width-w)/2,y=2,inner=w-4
        let success=state.impactExportURL != nil,ink:TerminalInk=success ? .good:.warning
        c.fillRow(y:0,fill:.panel);c.write(L10n.text(" TAWL / EXPORT REPORT"),x:0,y:0,ink:.cpu)
        c.box(x:x,y:y,width:w,height:h,title:success ? L10n.text("HTML REPORT SAVED"):L10n.text("COULD NOT SAVE REPORT"),ink:ink)
        var row=y+2
        func lines(_ value:String)->[String] {TerminalText.wrapped(value,to:inner)}
        if let url=state.impactExportURL {
            c.write(L10n.text("Charts + process + application + before/after values"),x:x+2,y:row,ink:.primary);row+=2
            c.write(L10n.text("FILE"),x:x+2,y:row,ink:.cpu);row+=1
            for line in lines(url.path).prefix(h-10) {c.write(line,x:x+2,y:row,ink:.primary);row+=1}
            row+=1
            c.write(L10n.text("One offline HTML file · existing files are not overwritten"),x:x+2,y:row,ink:.muted)
        }
        if !state.impactExportError.isEmpty {
            for line in lines(state.impactExportError).prefix(max(1,y+h-4-row)) {c.write(line,x:x+2,y:row,ink:.warning);row+=1}
        }
        c.write(success ? L10n.text("a: open in browser · Esc / Enter: back to comparison"):L10n.text("Esc / Enter: back to comparison · d to retry"),x:x+2,y:y+h-3,ink:.cpu)
        c.write(success ? L10n.text("Saved at this moment; live sampling continues in the background."):L10n.text("Comparison retained; run from a writable directory."),x:x+2,y:y+h-2,ink:.muted)
        c.fillRow(y:c.height-1,fill:.panel)
        c.write(L10n.text(" Esc / Enter back · ")+(success ? L10n.text("a open report · "):L10n.text("d retry · "))+L10n.text("q quit"),x:0,y:c.height-1,ink:.secondary)
    }
}
