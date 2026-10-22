import Foundation
import Darwin

/// A self-contained snapshot of the comparison. Exporting never mutates its
/// evidence, triggers process control, or loads remote fonts/scripts/assets.
public enum ClosureImpactExporter {
    public static func write(impact: ClosureImpact, status: ProcessClosureStatus, directory: URL,
                             exportedAt: Date = Date()) throws -> URL {
        guard directory.isFileURL else { throw CocoaError(.fileWriteUnsupportedScheme) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let directoryFD = Darwin.open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directoryFD >= 0 else { throw posixError() }
        defer { Darwin.close(directoryFD) }
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX"); stamp.timeZone = TimeZone(secondsFromGMT: 0)
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        let name = "tawl-kapatma-\(stamp.string(from: exportedAt))-pid\(impact.intent.pid)-\(UUID().uuidString.lowercased()).html"
        let fd = openat(directoryFD, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard fd >= 0 else { throw posixError() }
        var saved = false
        defer {
            Darwin.close(fd)
            if !saved { unlinkat(directoryFD, name, 0) }
        }
        // O_EXCL prevents overwrites; mode applies only to the newly created file.
        guard fchmod(fd, mode_t(0o600)) == 0 else { throw posixError() }
        let bytes = Data(html(impact: impact, status: status, exportedAt: exportedAt).utf8)
        try bytes.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(fd, base.advanced(by: offset), buffer.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw posixError() }
                offset += count
            }
        }
        saved = true
        return directory.appendingPathComponent(name)
    }

    private static func posixError() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }

    public static func html(impact: ClosureImpact, status: ProcessClosureStatus,
                            exportedAt: Date = Date()) -> String {
        let summary = impact.summary, intent = impact.intent
        let complete = impact.isComplete
        let phase = complete ? "Ölçüm tamamlandı" : "Kısmi rapor · \(seconds(impact.elapsed)) / 60 sn"
        let outcome = outcome(status, complete: complete)
        let metrics = metrics(impact)
        let rows = metrics.map { metric in
            "<tr><th scope=\"row\">\(escape(metric.title))<small>\(escape(metric.statistic))</small></th><td>\(escape(metric.before))<small>\(escape(metric.beforeDetail))</small></td><td>\(escape(metric.after))<small>\(escape(metric.afterDetail))</small></td><td class=\"delta\">\(escape(metric.delta))</td></tr>"
        }.joined(separator: "\n")
        let graphs = metrics.enumerated().map { index, metric in
            "<section class=\"chart\"><div class=\"chart-heading\"><div><span class=\"eyebrow\">SİSTEM GENELİ</span><h2>\(escape(metric.title))</h2></div><div class=\"chart-change\">\(escape(metric.before)) <span>→</span> \(escape(metric.after))<small>\(escape(metric.delta))</small></div></div><div class=\"plot-scroll\">\(chart(impact, metric: metric, index: index))</div><p class=\"chart-note\">\(escape(metric.note))</p></section>"
        }.joined(separator: "\n")
        let reasons = intent.reasons.map { "<li>\(escape($0))</li>" }.joined()
        let effects = intent.impact.map { "<li>\(escape($0))</li>" }.joined()
        let sampleCounts = "\(summary.before.sampleCount) önce / \(summary.after.sampleCount) sonra"
        return """
        <!doctype html>
        <html lang="tr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
        <title>TAWL · Kapatma karşılaştırması · \(escape(intent.applicationName)) · PID \(intent.pid)</title>
        <style>\(stylesheet)</style></head><body><main>
        <header><div class="brand">TAWL <span>/ KAYNAK RAPORU</span></div><span class="phase \(complete ? "complete" : "partial")">\(escape(phase))</span></header>
        <div class="intro"><p class="eyebrow">KAPATMA ÖNCESİ / SONRASI</p><h1>Kaynak kullanımında<br>ne değişti?</h1><p>Önceki 30 saniye ile isteği izleyen \(seconds(impact.elapsed)) saniyenin sistem ölçümleri.</p></div>
        <section class="identity"><div><span class="label">\(status == .exitObserved ? "Kapatılan süreç" : "Hedeflenen süreç")</span><h2>\(escape(intent.processName))</h2><p class="mono">PID \(intent.pid) <span class="muted">· Kimlik \(escape(intent.processID))</span></p></div><div><span class="label">Etkilenen uygulama</span><h2>\(escape(intent.applicationName))</h2><p>İstek anında \(intent.applicationMemberCount) süreç · yalnız seçili PID hedeflendi.</p></div></section>
        <div class="outcome \(outcome.2)"><strong>\(escape(outcome.0))</strong><p>\(escape(outcome.1))</p></div>
        <dl class="metadata"><div><dt>Kapatma isteği</dt><dd>\(escape(date(impact.startedOn)))</dd></div><div><dt>Dışa aktarıldığı an</dt><dd>\(escape(date(exportedAt)))</dd></div><div><dt>Örnek sayısı</dt><dd>\(sampleCounts)</dd></div></dl>
        \(complete ? "" : "<p class=\"partial-note\"><strong>Dışa aktarıldığı andaki durum.</strong> Bu dosya kendiliğinden güncellenmez. 60 saniye dolduğunda yeni rapor alabilirsin.</p>")
        <section class="comparison"><div class="section-title"><h2>Önce / sonra</h2><span>Süreç değil, sistem toplamı</span></div><div class="table-scroll"><table><thead><tr><th>Kaynak</th><th>Önce · son 30 sn</th><th>Sonra · ilk \(seconds(impact.elapsed)) sn</th><th>Değişim</th></tr></thead><tbody>\(rows)</tbody></table></div></section>
        <p class="mobile-hint">Tablo ve grafikleri yatay kaydırarak inceleyebilirsin.</p>
        <div class="legend"><span><i class="legend-line"></i> Gözlenen değer</span><span><i class="legend-request"></i> Kapatma isteği</span><span><i class="legend-missing"></i> Ölçüm yok</span><span><i class="legend-future"></i> Henüz gözlenmedi</span></div>
        \(graphs)
        <section class="interpretation"><h2>Bu rapor nasıl okunmalı?</h2><p>Gözlenen değişim, tek başına neden kanıtı değildir. Aynı anda çalışan diğer işler de CPU, bellek baskısı ve swap değerlerini değiştirebilir.</p><p>CPU ve swap yazımı geçerli ölçüm aralıklarının süre ağırlıklı ortalamasıdır. Eksik süreler ortalamaya sıfır olarak katılmaz. Bellek baskısı ve swap miktarı, her pencerenin sonundaki güncel ölçümü gösterir; 5 saniyeden eski değerler kullanılmaz.</p><p>Swap miktarındaki azalma, kapanan sürecin kullandığı swap veya geri kazanılan RAM değildir. Swap hemen düşmeyebilir. Grafiklerin zaman ekseni ortaktır; miktar ve yazım ölçekleri ayrı ayrı belirtilmiştir.</p></section>
        <section class="context"><div><h3>İstek anındaki öneri</h3><ul>\(reasons)</ul></div><div><h3>Onay öncesi gösterilen etki</h3><ul>\(effects)</ul></div></section>
        <footer><span>TAWL · Yerel ölçüm raporu</span><span>Tek dosya · Çevrimdışı açılır · Tarayıcıdan yazdırılabilir</span></footer>
        </main></body></html>
        """
    }

    private struct Metric {
        let title, statistic, before, after, delta, beforeDetail, afterDetail, note, color: String
        let kind: Kind
    }
    private enum Kind { case cpu, pressure, stock, writes }
    private struct Segment { let start, end, value: Double }

    private static func metrics(_ impact: ClosureImpact) -> [Metric] {
        let s = impact.summary
        func coverage(_ value: Double, _ total: Double) -> String { "Geçerli süre: \(seconds(value)) / \(seconds(total)) sn" }
        let latest = "Pencere sonundaki güncel ölçüm"
        return [
            Metric(title: "Sistem CPU", statistic: "Süre ağırlıklı ortalama", before: percent(s.before.cpu.value), after: percent(s.after.cpu.value),
                   delta: s.cpuDeltaPercentagePoints.map { signed($0, decimals: 1) + " puan" } ?? "Hesaplanamadı",
                   beforeDetail: coverage(s.before.cpu.coverageSeconds, 30), afterDetail: coverage(s.after.cpu.coverageSeconds, impact.elapsed),
                   note: "Sabit ölçek: 0–100%. Fark yüzde puandır; göreli yüzde değişimi değildir.", color: "#0879a6", kind: .cpu),
            Metric(title: "Bellek baskısı", statistic: "Kategorik durum · son ölçüm", before: pressure(s.before.pressure), after: pressure(s.after.pressure),
                   delta: s.before.pressure == .unknown || s.after.pressure == .unknown ? "Hesaplanamadı" : "\(pressure(s.before.pressure)) → \(pressure(s.after.pressure))",
                   beforeDetail: latest, afterDetail: latest,
                   note: "Normal, uyarı ve kritik ayrı durumlardır; sayısal ortalama alınmaz. Yeşil: normal · sarı: uyarı · kırmızı: kritik.", color: "#946100", kind: .pressure),
            Metric(title: "Swap miktarı", statistic: "Diskte kullanılan swap · son ölçüm", before: bytes(s.before.swapUsedBytes.map { Double($0) }), after: bytes(s.after.swapUsedBytes.map { Double($0) }),
                   delta: s.swapUsedDeltaBytes.map { signedBytes(Double($0)) } ?? "Hesaplanamadı", beforeDetail: latest, afterDetail: latest,
                   note: "Yakınlaştırılmış miktar ölçeği; önce ve sonra aynı ölçek kullanılır. Değişim, serbest kalan RAM miktarı değildir.", color: "#7a55b4", kind: .stock),
            Metric(title: "Swap yazımı", statistic: "RAM'den diske · süre ağırlıklı ortalama", before: rate(s.before.swapOut.value), after: rate(s.after.swapOut.value),
                   delta: s.swapOutDeltaBytesPerSecond.map { signedBytes($0) + "/s" } ?? "Hesaplanamadı",
                   beforeDetail: coverage(s.before.swapOut.coverageSeconds, 30), afterDetail: coverage(s.after.swapOut.coverageSeconds, impact.elapsed),
                   note: "Yeni swap yazım hızı. Ölçülmüş 0 B/s, bu aralıkta yeni swap yazılmadığı anlamına gelir; boş veya taralı alan sıfır değildir.", color: "#b6681a", kind: .writes)
        ]
    }

    private static func segments(_ impact: ClosureImpact, kind: Kind) -> [Segment] {
        let left = impact.startedAt - 30
        var result: [Segment] = []
        for (points, end) in [(impact.before, impact.startedAt), (impact.after, impact.startedAt + impact.elapsed)] {
            for (i, point) in points.enumerated() {
                let value: Double?
                switch kind {
                case .cpu: value = point.cpuPercent
                case .writes: value = point.swapOutBytesPerSecond
                case .stock: value = point.swapUsedBytes.map { Double($0) }
                case .pressure:
                    switch point.pressure { case .normal: value = 1; case .warning: value = 2; case .critical: value = 3; case .unknown: value = nil }
                }
                guard let value, value.isFinite, value >= 0 else { continue }
                let a: Double, b: Double
                if kind == .cpu || kind == .writes {
                    guard let duration = point.intervalSeconds else { continue }
                    a = max(left, point.time - duration); b = point.time
                } else {
                    a = max(left, point.time)
                    b = min(end, min(point.time + ClosureImpact.maximumInterval, i + 1 < points.count ? points[i + 1].time : end))
                }
                if b > a { result.append(Segment(start: a - impact.startedAt, end: b - impact.startedAt, value: value)) }
            }
        }
        return result
    }

    private static func chart(_ impact: ClosureImpact, metric: Metric, index: Int) -> String {
        let data = segments(impact, kind: metric.kind)
        let low: Double, high: Double
        switch metric.kind {
        case .cpu: low = 0; high = 100
        case .pressure: low = 0; high = 3
        case .stock:
            let minValue = data.map(\.value).min() ?? 0, maxValue = data.map(\.value).max() ?? 0
            let padding = max(64 * 1_048_576, (maxValue - minValue) * 0.1)
            low = max(0, minValue - padding); high = max(low + 1, maxValue + padding)
        case .writes: low = 0; high = max(1, data.map(\.value).max() ?? 0)
        }
        let px = 86.0, py = 28.0, pw = 850.0, ph = 116.0
        func x(_ t: Double) -> Double { px + ((t + 30) / 90) * pw }
        func y(_ v: Double) -> Double { py + ph * (1 - min(1, max(0, (v - low) / (high - low)))) }
        func n(_ value: Double) -> String { String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value) }
        var pieces: [String] = []
        pieces.append("<svg viewBox=\"0 0 960 182\" role=\"img\" aria-labelledby=\"chart-title-\(index) chart-desc-\(index)\" xmlns=\"http://www.w3.org/2000/svg\"><title id=\"chart-title-\(index)\">\(escape(metric.title)) · önce ve sonra</title><desc id=\"chart-desc-\(index)\">\(escape(metric.before)) → \(escape(metric.after)). −30 ile +60 saniye; kapatma isteği 0 noktasında. Taralı alan ölçüm eksikliğini gösterir.</desc>")
        pieces.append("<defs><pattern id=\"missing-\(index)\" patternUnits=\"userSpaceOnUse\" width=\"7\" height=\"7\"><path d=\"M0 7L7 0\" stroke=\"#d9dfe5\" stroke-width=\"1\"/></pattern></defs>")
        pieces.append("<rect x=\"\(n(px))\" y=\"\(n(py))\" width=\"\(n(pw))\" height=\"\(n(ph))\" fill=\"#fafbfd\"/>")
        if impact.elapsed < 60 {
            pieces.append("<rect class=\"future-region\" x=\"\(n(x(impact.elapsed)))\" y=\"\(n(py))\" width=\"\(n(x(60) - x(impact.elapsed)))\" height=\"\(n(ph))\" fill=\"#edf0f3\"/>")
        }
        var cursor = -30.0
        for segment in data.sorted(by: { $0.start < $1.start }) {
            if segment.start > cursor { pieces.append(gap(cursor, min(impact.elapsed, segment.start), index: index, x: x, n: n, py: py, ph: ph)) }
            cursor = max(cursor, segment.end)
        }
        if cursor < impact.elapsed { pieces.append(gap(cursor, impact.elapsed, index: index, x: x, n: n, py: py, ph: ph)) }
        let gridValues = metric.kind == .pressure ? [1.0, 2.0, 3.0] : [low, (low + high) / 2, high]
        for value in gridValues {
            let label: String
            switch metric.kind {
            case .pressure: label = value == 1 ? "Normal" : value == 2 ? "Uyarı" : "Kritik"
            case .cpu: label = "\(Int(value))%"
            case .stock: label = data.isEmpty ? "—" : bytes(value)
            case .writes: label = data.isEmpty ? "—" : rate(value)
            }
            pieces.append("<path d=\"M\(n(px)) \(n(y(value)))H\(n(px + pw))\" stroke=\"#e2e6eb\"/><text x=\"74\" y=\"\(n(y(value) + 4))\" text-anchor=\"end\" class=\"axis\">\(escape(label))</text>")
        }
        for segment in data {
            let color = metric.kind == .pressure ? (segment.value == 1 ? "#25805b" : segment.value == 2 ? "#b27a0a" : "#bd4848") : metric.color
            let a = x(segment.start), b = x(segment.end), top = y(segment.value)
            pieces.append("<rect data-observed=\"\(n(segment.value))\" x=\"\(n(a))\" y=\"\(n(top))\" width=\"\(n(max(0, b-a)))\" height=\"\(n(max(0, py + ph - top)))\" fill=\"\(color)\" opacity=\"0.14\"/><path d=\"M\(n(a)) \(n(top))H\(n(b))\" stroke=\"\(color)\" stroke-width=\"2.5\" fill=\"none\"/>")
        }
        pieces.append("<path class=\"request-line\" d=\"M\(n(x(0))) 21V151\" stroke=\"#24364c\" stroke-width=\"1.5\" stroke-dasharray=\"4 3\"/><text x=\"\(n(x(0) + 8))\" y=\"15\" class=\"request-label\">0 · KAPATMA İSTEĞİ</text>")
        for tick in [-30.0, 0, 30, 60] {
            let label = tick == 0 ? "0 sn" : "\(tick > 0 ? "+" : "−")\(Int(abs(tick))) sn"
            pieces.append("<text x=\"\(n(x(tick)))\" y=\"169\" text-anchor=\"\(tick == -30 ? "start" : tick == 60 ? "end" : "middle")\" class=\"axis\">\(label)</text>")
        }
        pieces.append("</svg>")
        return pieces.joined()
    }

    private static func gap(_ a: Double, _ b: Double, index: Int, x: (Double) -> Double,
                            n: (Double) -> String, py: Double, ph: Double) -> String {
        guard b > a else { return "" }
        return "<rect class=\"missing-region\" x=\"\(n(x(a)))\" y=\"\(n(py))\" width=\"\(n(x(b) - x(a)))\" height=\"\(n(ph))\" fill=\"url(#missing-\(index))\"/>"
    }

    private static func outcome(_ status: ProcessClosureStatus, complete: Bool) -> (String, String, String) {
        switch status {
        case .exitObserved: return ("Süreç çıkışı doğrulandı", "Hedeflenen süreç kimliğinin sonlandığı işletim sisteminden doğrulandı. Sistem kaynaklarındaki fark aşağıda ayrı gösterilir.", "confirmed")
        case .identityChanged: return ("Süreç kimliği değişti", "Aynı PID artık başka bir süreç kimliğine ait. Eski sürecin kapatma isteğiyle sonlandığı doğrulanamadı.", "uncertain")
        case .stillRunning: return ("Son kontrolde süreç hâlâ çalışıyordu", "Kapatma isteği kabul edildi; kapanma doğrulanmadı. Bu rapor zorla kapatma sonucu içermez.", "uncertain")
        case .waitingForExit, .submitting:
            return ("Kapanma henüz doğrulanmadı", complete ? "Gözlem penceresi bitti. Kapatma isteğinin kabul edilmesi, sürecin sonlandığını tek başına kanıtlamaz." : "Kapatma isteği işlendi; dışa aktarma anında süreç çıkışı doğrulanmamıştı.", "uncertain")
        case .unverified: return ("Süreç sonucu doğrulanamadı", "Son kontrolde hedef kimliğin durumu okunamadı veya gözlem kesildi. Kaynak grafikleri kapanma kanıtı değildir.", "uncertain")
        case .rejected(let reason): return ("Kapatma isteği reddedildi", reason, "uncertain")
        case .cancelled: return ("Kapatma iptal edildi", "Kapatma isteği gönderilmedi.", "uncertain")
        case .preview: return ("Kapatma henüz onaylanmadı", "Bu durum bir süreç kapanmasını doğrulamaz.", "uncertain")
        }
    }
    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
    private static func date(_ value: Date) -> String {
        guard value.timeIntervalSince1970.isFinite else { return "Bilinmiyor" }
        let formatter = ISO8601DateFormatter(); formatter.timeZone = TimeZone.current
        return formatter.string(from: value)
    }
    private static func seconds(_ value: Double) -> String {
        String(format: value.rounded() == value ? "%.0f" : "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
    private static func percent(_ value: Double?) -> String {
        value.map { String(format: "%.1f%%", locale: Locale(identifier: "en_US_POSIX"), $0) } ?? "Ölçüm yok"
    }
    private static func pressure(_ value: Pressure) -> String {
        switch value { case .normal: return "Normal"; case .warning: return "Uyarı"; case .critical: return "Kritik"; case .unknown: return "Ölçüm yok" }
    }
    private static func signed(_ value: Double, decimals: Int) -> String {
        let sign = value > 0 ? "+" : value < 0 ? "−" : ""
        return sign + String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"), decimals, abs(value))
    }
    private static func bytes(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "Ölçüm yok" }
        let units = ["B", "KiB", "MiB", "GiB", "TiB", "PiB", "EiB"]
        var size = value, index = 0
        while size >= 1024 && index < units.count - 1 { size /= 1024; index += 1 }
        return String(format: index == 0 && (size == 0 || size >= 1) ? "%.0f %@" : "%.1f %@", locale: Locale(identifier: "en_US_POSIX"), size, units[index])
    }
    private static func signedBytes(_ value: Double) -> String {
        (value > 0 ? "+" : value < 0 ? "−" : "") + bytes(abs(value))
    }
    private static func rate(_ value: Double?) -> String { value.map { bytes($0) + "/s" } ?? "Ölçüm yok" }

    private static let stylesheet = """
    :root{color-scheme:light;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color:#203047;background:#edf1f5;font-synthesis:none}*{box-sizing:border-box}body{margin:0;padding:40px 20px}main{max-width:1080px;margin:auto;padding:40px 48px;background:#fff;border-top:5px solid #0879a6;box-shadow:0 8px 50px #1933490c}header,.section-title,.chart-heading,footer{display:flex;justify-content:space-between;align-items:center;gap:20px}.brand{font-size:17px;font-weight:800;letter-spacing:.1em;color:#0879a6}.brand span{font-size:12px;letter-spacing:.08em;color:#5b697a;margin-left:10px}.phase{font-size:12px;font-weight:700;padding:8px 11px;border:1px solid #d9e5eb;border-radius:4px;background:#eef6f8}.phase.partial{color:#885e10;background:#fff8e8;border-color:#ead6a7}.intro{margin:40px 0 30px}.eyebrow,.label{font-size:12px;letter-spacing:.11em;font-weight:700;color:#5b697a}.intro h1{font-size:42px;line-height:1.1;letter-spacing:-.04em;margin:10px 0 16px;font-weight:750}.intro p:last-child{font-size:15px;color:#5f6d7f}.identity{display:grid;grid-template-columns:1fr 1fr;gap:30px;background:#f5f8fa;border-top:1px solid #dce5eb;border-bottom:1px solid #dce5eb;padding:22px 24px}.identity h2{font-size:19px;margin:8px 0;overflow-wrap:anywhere}.identity p{font-size:14px;line-height:1.6;margin:0;color:#58677a;overflow-wrap:anywhere}.mono{font-family:ui-monospace,Menlo,monospace}.muted{color:#5f6f82}.outcome{margin-top:16px;padding:14px 18px;border-left:3px solid #248360;background:#f0f8f4}.outcome.uncertain{border-color:#ba8424;background:#fff9ed}.outcome strong{font-size:14px}.outcome p{margin:5px 0 0;font-size:14px;line-height:1.6;color:#58677a;overflow-wrap:anywhere}.metadata{display:grid;grid-template-columns:1fr 1fr 1fr;gap:20px;margin:22px 0 30px}.metadata dt{font-size:12px;color:#5c6e82;margin-bottom:5px}.metadata dd{margin:0;font-size:13px;font-variant-numeric:tabular-nums;overflow-wrap:anywhere}.partial-note{font-size:14px;line-height:1.6;padding:14px 18px;background:#fff9ed;border:1px solid #efddb7;margin:0 0 25px}.section-title{margin-bottom:12px}.section-title h2{font-size:20px;margin:0}.section-title span{font-size:12px;color:#5c6e82}.table-scroll{overflow-x:auto}table{width:100%;border-collapse:collapse;font-size:14px;font-variant-numeric:tabular-nums}thead{background:#213a50;color:#fff;text-align:right}th,td{padding:14px 14px;border-bottom:1px solid #e2e8ee;text-align:right;vertical-align:top}th:first-child{text-align:left;width:30%}thead th{font-size:12px;font-weight:600;white-space:nowrap}tbody th{font-size:14px;font-weight:650}tbody td{font-weight:650;white-space:nowrap}small{display:block;font-size:12px;line-height:1.5;margin-top:5px;font-weight:400;color:#5c6e82}td.delta{color:#335e80}tbody tr:last-child td,tbody tr:last-child th{border-bottom:2px solid #d7e0e8}.mobile-hint{display:none}.plot-scroll{overflow-x:auto}.legend{display:flex;gap:22px;flex-wrap:wrap;font-size:12px;color:#5c6e82;margin:26px 0 4px}.legend span{display:flex;align-items:center;gap:7px}.legend i{display:inline-block;width:18px;height:9px}.legend-line{background:#0879a6;height:2px!important}.legend-request{border-left:2px dashed #24364c;width:2px!important;margin:0 8px}.legend-missing{background:repeating-linear-gradient(-45deg,#fff,#fff 3px,#cfd7df 3px,#cfd7df 4px);border:1px solid #dde3e9}.legend-future{background:#edf0f3;border:1px solid #e1e5eb}.chart{padding:25px 0 17px;border-bottom:1px solid #e2e8ee;break-inside:avoid}.chart h2{font-size:19px;margin:5px 0}.chart .eyebrow{font-size:12px}.chart-change{font-variant-numeric:tabular-nums;font-weight:700;font-size:18px;text-align:right}.chart-change span{padding:0 7px;font-weight:400;color:#97a4b3}.chart-change small{font-size:12px;color:#59758d}.chart svg{display:block;width:100%;height:auto;margin-top:12px}.axis{font-size:12px;fill:#576b80;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;font-variant-numeric:tabular-nums}.request-label{font-size:12px;fill:#24364c;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;letter-spacing:.07em;font-weight:700}.chart-note{margin:2px 0 0 9%;font-size:14px;line-height:1.6;color:#586c81}.interpretation{margin:30px 0 25px;padding-left:20px;border-left:3px solid #dce5ec}.interpretation h2{font-size:16px;margin:0 0 9px}.interpretation p{font-size:14px;line-height:1.7;color:#5e6f80;margin:8px 0}.context{display:grid;grid-template-columns:1fr 1.4fr;gap:34px;border-top:1px solid #e2e8ee;padding-top:18px}.context h3{font-size:14px;margin:0 0 8px}.context ul{padding-left:17px;margin:0}.context li{font-size:14px;line-height:1.65;color:#5c6e82;margin-bottom:5px;overflow-wrap:anywhere}footer{border-top:1px solid #dce5ec;margin-top:28px;padding-top:18px;font-size:12px;color:#5c6e82}@media(max-width:700px){.mobile-hint{display:block;font-size:12px;color:#5c6e82;margin-top:20px}.plot-scroll svg{min-width:760px}body{padding:0}main{padding:24px 18px}.intro{margin-top:28px}.intro h1{font-size:34px}.brand span{display:none}header{gap:10px}.phase{font-size:12px}.identity,.metadata,.context{grid-template-columns:1fr;gap:18px}.identity{padding:18px}.chart-heading{gap:10px}.chart h2{font-size:16px}.chart-change{font-size:14px}.section-title span{max-width:100px;text-align:right}.chart-note{margin-left:0}.legend{gap:14px}table{min-width:620px}footer{align-items:flex-start;line-height:1.6}}@page{size:A4;margin:14mm}@media print{html{background:#fff}.mobile-hint{display:none}.plot-scroll{overflow:visible}.plot-scroll svg{min-width:0}body{padding:0;background:#fff}main{max-width:none;padding:0;border-top:3px solid #0879a6;box-shadow:none}.intro{margin:24px 0}.intro h1{font-size:32px}.identity,.outcome,.metadata,.comparison,.context,.interpretation{break-inside:avoid}.chart{padding:17px 0 10px}.chart svg{max-height:150px}.chart-note{margin-left:0}.table-scroll{overflow:visible}table{min-width:0}.legend{margin-top:20px}*{-webkit-print-color-adjust:exact;print-color-adjust:exact}}
    """
}
