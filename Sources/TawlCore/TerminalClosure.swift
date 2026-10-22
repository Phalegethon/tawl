import Foundation

extension TerminalState {
    public mutating func beginClosure(using controller: ProcessClosureControlling, now: Double, candidate: ProcessSample? = nil) {
        guard closureSession == nil else { return }
        guard detailVisible || closureControlVisible, let process = candidate ?? selectedProcess, let snapshot = visibleSnapshot else {
            notice = "x ile kapatma penceresini aç; bir süreç seç."; return
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
            notice = "Önce aşağı kaydırıp etki bilgisinin tamamını incele."; return
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
        guard closureImpact != nil else { notice = "Henüz gönderilmiş kapatma isteği yok; karşılaştırma bulunmuyor."; return }
        impactVisible = true; searchEditing = false; helpVisible = false
    }

}

extension TerminalRenderer {
    static func closureOutcome(_ status: ProcessClosureStatus) -> (String, String, TerminalInk) {
        switch status {
        case .preview: return ("ONAY BEKLİYOR", "Henüz istek gönderilmedi. Varsayılan seçim Vazgeç.", .warning)
        case .cancelled: return ("VAZGEÇİLDİ", "Sürece herhangi bir istek gönderilmedi.", .secondary)
        case .submitting: return ("KİMLİK DOĞRULANIYOR", "Hedef süreç ve uygulama yeniden denetleniyor.", .cpu)
        case .waitingForExit: return ("İSTEK GÖNDERİLDİ · BEKLENİYOR", "SIGTERM kabul edildi; sürecin çıktığı henüz doğrulanmadı.", .warning)
        case .exitObserved: return ("SEÇİLİ SÜRECİN ÇIKIŞI DOĞRULANDI", "İlk süreç kimliği artık çalışmıyor. Uygulama başka bir süreç başlatabilir.", .good)
        case .identityChanged: return ("HEDEF KİMLİĞİ DEĞİŞTİ", "Önceki kimlik artık eşleşmiyor; yeni kimliğe istek gönderilmedi. Kapanma doğrulanamadı.", .warning)
        case .stillRunning: return ("SÜREÇ HÂLÂ ÇALIŞIYOR", "10 sn geçti. Zorla kapatma yapılmadı; uygulamayı kendi menüsünden incele.", .warning)
        case .unverified: return ("SONUÇ DOĞRULANAMADI", "Süreç durumu okunamıyor. Yeniden istek veya zorla kapatma yapılmadı.", .warning)
        case .rejected(let message): return ("İSTEK GÖNDERİLMEDİ", message, .danger)
        }
    }
    static func closureView(_ c: inout TerminalCanvas, _ state: TerminalState) -> Int {
        guard let session = state.closureSession else { return 0 }
        let intent = session.intent, outcome = closureOutcome(session.status)
        let w = min(c.width-4, 100), x = (c.width-w)/2, y = 2
        let h = min(c.height-4, 20), inner = w-4
        c.fillRow(y: 0, fill: .panel)
        c.write(" TAWL / SÜREÇ KAPATMA · " + (session.status == .preview ? "2 ONAY":"3 SONUÇ"), x: 0, y: 0, ink: .cpu)
        c.box(x:x,y:y,width:w,height:h,title:outcome.0,ink:outcome.2)
        var doc = TerminalCanvas(width:inner,height:200), row = 0
        section(&doc,"ETKİLENECEK UYGULAMA",x:0,y:row,w:inner,ink:.cpu); row+=1
        row=paragraph(&doc,intent.applicationName,x:0,y:row,w:inner,ink:.primary)
        row=paragraph(&doc,"PID \(intent.pid) · \(intent.processName)",x:0,y:row,w:inner,ink:.secondary)
        row=paragraph(&doc,"Uygulamada \(intent.applicationMemberCount) gözlenen süreç · hedef yalnız 1 süreç",x:0,y:row,w:inner,ink:.muted)+1
        if session.status == .preview {
            row=paragraph(&doc,"◆ "+intent.reasons.joined(separator:" · "),x:0,y:row,w:inner,ink:.warning)
            row=paragraph(&doc,"Sekme, pencere veya arka plan işi kesilebilir; uygulamanın tamamı da etkilenebilir.",x:0,y:row,w:inner)+1
            row=paragraph(&doc,"Kaydedilmemiş değişiklikler kaybolabilir. Önce çalışmalarını kaydet.",x:0,y:row,w:inner,ink:.warning)
            row=paragraph(&doc,"Yöntem: SIGTERM · kayıt diyaloğu garantisi yok. Zorla kapatma yok.",x:0,y:row,w:inner,ink:.muted)
            row=paragraph(&doc,"Diğer süreçlere doğrudan istek gönderilmez. Onay 30 sn geçerlidir.",x:0,y:row,w:inner,ink:.muted)
        } else {
            section(&doc,outcome.0,x:0,y:row,w:inner,ink:outcome.2); row+=1
            row=paragraph(&doc,outcome.1,x:0,y:row,w:inner,ink:outcome.2)+1
            row=paragraph(&doc,"Kapsam: yalnız PID \(intent.pid). Bu sonuç, uygulamanın tamamının kapandığı anlamına gelmez.",x:0,y:row,w:inner)
            row=paragraph(&doc,"Bellek baskısını ve swap yazımını izleyebilirsin. Boşalacak bellek/swap miktarı garanti edilmez.",x:0,y:row+1,w:inner,ink:.muted)
        }
        let capacity = h-5, limit = max(0,row-capacity), offset = min(state.closureScroll,limit)
        c.copy(doc,fromRow:offset,toX:x+2,toY:y+1,rowCount:capacity)
        let buttonsY = y+h-3
        if session.status == .preview {
            let cancel = session.choice == .cancel, label = "Sonlandırma isteği gönder", ready = offset >= limit
            c.write(cancel ? "› Vazgeç":"  Vazgeç",x:x+2,y:buttonsY,ink:cancel ? .primary:.secondary,fill:cancel ? .selected:.panel)
            c.write((cancel ? "  ":"› ")+label,x:x+17,y:buttonsY,ink:ready ? (cancel ? .warning:.primary):.muted,fill:cancel ? .panel:.selected)
            c.write(ready ? "←/→ veya Tab seç · Enter/Space uygula · Esc vazgeç":"↑↓ Etki bilgisini sona kadar oku; sonra onayla.",x:x+2,y:buttonsY+1,ink:ready ? .muted:.warning)
        } else {
            c.write("Esc / Enter / Space: süreçlere dön",x:x+2,y:buttonsY,ink:.cpu)
            c.write("Otomatik tekrar veya SIGKILL uygulanmaz.",x:x+2,y:buttonsY+1,ink:.muted)
        }
        c.fillRow(y:c.height-1,fill:.panel)
        c.write(limit>0 ? " ↑↓ / PgUp/PgDn ayrıntı kaydır · Esc geri · q çıkış":" Esc geri · q çıkış",x:0,y:c.height-1,ink:.secondary)
        if limit>0 { c.write(" \(offset+1)–\(min(row,offset+capacity))/\(row) ↑↓ ",x:x+w-22,y:y+h-1,ink:.cpu) }
        return limit
    }
}
