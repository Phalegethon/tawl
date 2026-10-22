import XCTest
@testable import TawlCore

final class ProcessAssessmentTests: XCTestCase {
    let mib: UInt64 = 1_048_576
    func process(cpu: Double? = 0.01, memory: UInt64 = 512 * 1_048_576) -> ProcessSample {
        var p = ProcessSample(id: "42:100", pid: 42, name: "Browser Helper", applicationID: "app:browser",
                              applicationName: "Browser", cpuCores: cpu, footprintBytes: memory,
                              diskReadBytesPerSecond: 0, diskWriteBytesPerSecond: 0)
        p.ageSeconds = 10_000; p.canReviewClosure = true
        return p
    }
    func history(_ process: ProcessSample, duration: Int = 600) -> [Snapshot] {
        stride(from: 0, through: duration, by: 2).map { time in
            var s = Snapshot(timestamp: Date(timeIntervalSince1970: Double(time)), monotonicTime: Double(time))
            s.intervalSeconds = 2; s.pressure = .normal; s.processes = [process]
            return s
        }
    }
    func assess(_ p: ProcessSample, _ h: [Snapshot]) -> ProcessAssessment {
        assessProcess(p, snapshot: h.last!, history: h)
    }
    func testResourceBadgesIdentifySpecificResourceAndSeverity() {
        let values = resourceSignals(cpuCores: 2, footprintBytes: 4 * 1024 * mib, memoryDeltaBytes: Int64(100 * mib))
        XCTAssertEqual(values.map(\.label), ["CPU", "MEMORY", "GROWTH"])
        XCTAssertEqual(values.map(\.severity), [.critical, .critical, .warning])
        XCTAssertTrue(resourceSignals(cpuCores: .nan, footprintBytes: nil, memoryDeltaBytes: -1).isEmpty)
        XCTAssertTrue(resourceSignals(cpuCores: 0.9, footprintBytes: 1024 * mib, memoryDeltaBytes: 50).isEmpty)
    }
    func testCPUAdviceRequiresThirtySecondsAndNamesTheOwningApp() {
        let p = process(cpu: 1.2)
        XCTAssertTrue(assess(p, history(p, duration: 28)).recommendations.isEmpty)
        let result = assess(p, history(p, duration: 30))
        XCTAssertEqual(result.recommendations.first?.kind, .sustainedCPU)
        XCTAssertTrue(result.recommendations.first?.action.contains("Browser") == true)
        XCTAssertTrue(result.recommendations.first?.evidence.contains("30") == true)
    }
    func testLocalizedRecommendationPreservesApplicationNamesThatMatchTranslationKeys() {
        var p = process(cpu: 1.2)
        p.applicationName = "Memory pressure"
        let english = L10n.withLanguage(.english) { assess(p, history(p, duration: 30)) }
        let turkish = L10n.withLanguage(.turkish) { assess(p, history(p, duration: 30)) }
        XCTAssertEqual(english.recommendations.map(\.kind), turkish.recommendations.map(\.kind))
        XCTAssertNotEqual(english.recommendations.first?.title, turkish.recommendations.first?.title)
        XCTAssertTrue(english.recommendations.first?.action.contains("Memory pressure") == true)
        XCTAssertTrue(turkish.recommendations.first?.action.contains("Memory pressure") == true)
        XCTAssertEqual(english.highCPUSeconds, turkish.highCPUSeconds)
    }
    func testMissingMetricsSamplingGapsAndPIDReuseBreakSustainedCPU() {
        let p = process(cpu: 1.2)
        var samples = history(p, duration: 40)
        samples[10].processes[0].cpuCores = nil
        XCTAssertTrue(assess(p, samples).recommendations.isEmpty)
        samples = history(p, duration: 40); samples[10].processes[0].id = "42:old"
        XCTAssertTrue(assess(p, samples).recommendations.isEmpty)
        samples = [history(p, duration: 0)[0], history(p, duration: 40).last!]
        XCTAssertTrue(assess(p, samples).recommendations.isEmpty)
    }
    func testLargeMemoryOnlySuggestsClosureAlongsidePressure() {
        let p = process(memory: 3 * 1024 * mib)
        var samples = history(p, duration: 2)
        XCTAssertTrue(assess(p, samples).recommendations.isEmpty)
        samples[1].pressure = .warning
        XCTAssertEqual(assess(p, samples).recommendations.first?.kind, .memoryPressure)
    }
    func testQuietMemoryCandidateRequiresAgeAndTenMinutesOfCPUAndIOEvidence() {
        let p = process()
        XCTAssertFalse(assess(p, history(p, duration: 598)).recommendations.contains { $0.kind == .quietMemory })
        let result = assess(p, history(p))
        XCTAssertEqual(result.recommendations.first?.kind, .quietMemory)
        XCTAssertTrue(result.recommendations.first?.caveat.contains("unused") == true)
        XCTAssertTrue(result.recommendations.first?.caveat.contains("network") == true)
        XCTAssertEqual(result.quietObservationState, .qualified)
        XCTAssertEqual(result.quietSeconds, 600)
    }
    func testTypedProgressDistinguishesUnknownFromObservedZeroAndDuration() {
        let p = process()
        let observing = assess(p, history(p, duration: 120))
        XCTAssertEqual(observing.quietObservationState, .observing)
        XCTAssertEqual(observing.quietSeconds, 120)
        var missing = p; missing.diskReadBytesPerSecond = .nan
        XCTAssertEqual(assess(missing, history(missing)).quietObservationState, .missingMetrics)
        XCTAssertNil(assess(missing, history(missing)).quietSeconds)
        var active = p; active.diskReadBytesPerSecond = 2048
        XCTAssertEqual(assess(active, history(active)).quietObservationState, .active)
        XCTAssertEqual(assess(active, history(active)).quietSeconds, 0)
        var young = p; young.ageSeconds = 300
        XCTAssertEqual(assess(young, history(young)).quietObservationState, .young)
        XCTAssertNil(assess(young, history(young)).quietSeconds)
        var protected = p; protected.canReviewClosure = false
        XCTAssertEqual(assess(protected, history(protected)).quietObservationState, .protected)
        XCTAssertNil(assess(protected, history(protected)).highCPUSeconds)
        var busy = p; busy.cpuCores = 2
        XCTAssertEqual(assess(busy, history(busy, duration: 10)).highCPUSeconds, 10)
        XCTAssertEqual(assess(busy, history(busy, duration: 40)).highCPUSeconds, 30)
    }
    func testUnknownAgeAndUnknownOrActiveIOCannotProduceQuietAdvice() {
        var p = process(); p.ageSeconds = nil
        XCTAssertFalse(assess(p, history(p)).recommendations.contains { $0.kind == .quietMemory })
        XCTAssertTrue(assess(p, history(p)).idleStatus.contains("age"))
        p = process(); p.diskReadBytesPerSecond = nil
        XCTAssertFalse(assess(p, history(p)).recommendations.contains { $0.kind == .quietMemory })
        p.diskReadBytesPerSecond = 1024
        XCTAssertFalse(assess(p, history(p)).recommendations.contains { $0.kind == .quietMemory })
        p = process(); p.ageSeconds = 7199
        XCTAssertFalse(assess(p, history(p)).recommendations.contains { $0.kind == .quietMemory })
    }
    func testMissingMemoryAndExitedSamplesNeverProduceQuietAdvice() {
        let p = process()
        var samples = history(p); samples[150].processes[0].footprintBytes = nil
        XCTAssertFalse(assess(p, samples).recommendations.contains { $0.kind == .quietMemory })
        samples = history(p); samples[samples.count-1].processes = []
        let result = assess(p, samples)
        XCTAssertTrue(result.recommendations.isEmpty)
        XCTAssertTrue(result.signals.isEmpty)
    }
    func testProtectedOrLegacyProcessesNeverReceiveClosureAdvice() {
        var p = process(cpu: 2, memory: 5 * 1024 * mib)
        p.canReviewClosure = false
        var samples = history(p); samples[samples.count-1].pressure = .critical
        let result = assess(p, samples)
        XCTAssertFalse(result.signals.isEmpty)
        XCTAssertTrue(result.recommendations.isEmpty)
        p.canReviewClosure = nil
        XCTAssertTrue(assess(p, history(p)).recommendations.isEmpty)
    }
    func testVMDatabaseAndSystemFamiliesKeepSignalsButNeverReceiveClosureOrQuietAdvice() {
        for name in ["Docker", "Parallels Desktop", "PostgreSQL", "WindowServer"] {
            var p = process(cpu: 2, memory: 5 * 1024 * mib)
            p.applicationName = name
            var samples = history(p)
            samples[samples.count - 1].pressure = .critical
            let busy = assess(p, samples)
            XCTAssertFalse(busy.signals.isEmpty, name)
            XCTAssertTrue(busy.recommendations.isEmpty, name)
            XCTAssertTrue(busy.idleStatus.contains("service"), name)
            p.cpuCores = 0.01
            XCTAssertTrue(assess(p, history(p)).recommendations.isEmpty, name)
        }
    }
    func testDatabaseWorkerInsideAnOtherwiseEligibleAppRemainsProtected() {
        var p = process(cpu: 2, memory: 5 * 1024 * mib)
        p.applicationName = "Visual Studio Code"
        p.name = "postgres"
        let result = assess(p, history(p))
        XCTAssertTrue(result.recommendations.isEmpty)
        XCTAssertTrue(result.idleStatus.contains("Databases"))
    }
    func testFutureSnapshotsDoNotSupplyEvidenceForHistoricalView() {
        let p = process(cpu: 2)
        let samples = history(p, duration: 60)
        XCTAssertTrue(assessProcess(p, snapshot: samples[5], history: samples).recommendations.isEmpty)
    }
    func testReducerExportsAgeAndOnlyOwnThirdPartyAppEligibility() {
        var raw = RawReading(timestamp: Date(timeIntervalSince1970: 10_000), monotonicTime: 20)
        var p = RawProcess(pid: 42, startedAt: 1_000_000_000, name: "Browser",
                           executablePath: "/Applications/Browser.app/Contents/MacOS/Browser")
        p.isOwnedByCurrentUser = true; raw.processes = [p]
        let safe = SnapshotReducer().reduce(raw).processes[0]
        XCTAssertEqual(safe.ageSeconds, 9000)
        XCTAssertEqual(safe.canReviewClosure, true)
        p.isOwnedByCurrentUser = false; raw.processes = [p]
        XCTAssertEqual(SnapshotReducer().reduce(raw).processes[0].canReviewClosure, false)
        p.isOwnedByCurrentUser = true; p.executablePath = "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal"
        raw.processes = [p]
        XCTAssertEqual(SnapshotReducer().reduce(raw).processes[0].canReviewClosure, false)
        p.executablePath = nil; raw.processes = [p]
        XCTAssertEqual(SnapshotReducer().reduce(raw).processes[0].canReviewClosure, false)
    }
    func testLegacyProcessRecordDecodesWithUnknownAgeAndEligibility() throws {
        var p = process(); p.ageSeconds = nil; p.canReviewClosure = nil
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(ProcessSample.self, from: data)
        XCTAssertNil(decoded.ageSeconds)
        XCTAssertNil(decoded.canReviewClosure)
    }
    func testStreamingEvidenceSurvivesEvictionOfDetailedHistory() {
        let p = process()
        let samples = history(p)
        var tracker = ProcessEvidenceTracker()
        for sample in samples { tracker.update(sample) }
        let current = samples.last!
        let evidence = tracker.evidence(for: p, at: current)
        XCTAssertEqual(evidence?.quietSeconds, 600)
        let result = assessProcess(p, snapshot: current, history: Array(samples.suffix(2)), evidence: evidence)
        XCTAssertTrue(result.recommendations.contains { $0.kind == .quietMemory })
        var later = current; later.monotonicTime += 2
        tracker.update(later)
        XCTAssertEqual(tracker.evidence(for: p, at: later)?.quietSeconds, 600)
    }
    func testStreamingEvidenceBreaksOnMissingRatesSamplingGapAndClockReset() {
        let p = process(cpu: 2)
        let samples = history(p, duration: 40)
        var tracker = ProcessEvidenceTracker()
        for sample in samples { tracker.update(sample) }
        XCTAssertEqual(tracker.evidence(for: p, at: samples.last!)?.highCPUSeconds, 30)
        var missing = samples.last!; missing.monotonicTime += 2
        missing.processes[0].cpuCores = nil
        tracker.update(missing)
        XCTAssertEqual(tracker.evidence(for: missing.processes[0], at: missing)?.highCPUSeconds, 0)
        var resumed = missing; resumed.monotonicTime += 2; resumed.processes = [p]
        tracker.update(resumed)
        XCTAssertEqual(tracker.evidence(for: p, at: resumed)?.highCPUSeconds, 0)
        var gap = resumed; gap.monotonicTime += 20; gap.intervalSeconds = 20
        tracker.update(gap)
        XCTAssertEqual(tracker.evidence(for: p, at: gap)?.highCPUSeconds, 0)
        tracker.update(samples[0])
        XCTAssertEqual(tracker.evidence(for: p, at: samples[0])?.highCPUSeconds, 0)
    }
    func testStreamingEvidenceCannotCrossExitedOrReusedProcessLifetimes() {
        let p = process(cpu: 2)
        let samples = history(p, duration: 40)
        var tracker = ProcessEvidenceTracker()
        for sample in samples { tracker.update(sample) }
        var absent = samples.last!; absent.monotonicTime += 2; absent.processes = []
        tracker.update(absent)
        XCTAssertEqual(tracker.trackedProcessCount, 0)
        XCTAssertNil(tracker.evidence(for: p, at: absent))
        var reused = absent; reused.monotonicTime += 2
        var replacement = p; replacement.id = "42:new"; reused.processes = [replacement]
        tracker.update(reused)
        XCTAssertEqual(tracker.trackedProcessCount, 1)
        XCTAssertNil(tracker.evidence(for: p, at: reused))
        XCTAssertEqual(tracker.evidence(for: replacement, at: reused)?.highCPUSeconds, 0)
    }
    func testStreamingEvidenceRejectsOldTimeAndChangedSnapshotMetrics() {
        let p = process(cpu: 2)
        let samples = history(p, duration: 40)
        var tracker = ProcessEvidenceTracker()
        for sample in samples { tracker.update(sample) }
        XCTAssertNil(tracker.evidence(for: p, at: samples[5]))
        let evidence = tracker.evidence(for: p, at: samples.last!)
        XCTAssertTrue(assessProcess(p, snapshot: samples[5], history: [samples[5]], evidence: evidence).recommendations.isEmpty)
        var changed = samples.last!; changed.processes[0].cpuCores = 0.01
        XCTAssertNil(tracker.evidence(for: p, at: changed))
    }
    func testStreamingQuietEvidenceRequiresEveryCPUMemoryAndDiskSample() {
        let p = process()
        for invalidField in 0..<3 {
            var samples = history(p)
            if invalidField == 0 { samples[150].processes[0].cpuCores = nil }
            if invalidField == 1 { samples[150].processes[0].footprintBytes = nil }
            if invalidField == 2 { samples[150].processes[0].diskWriteBytesPerSecond = nil }
            var tracker = ProcessEvidenceTracker()
            for sample in samples { tracker.update(sample) }
            let current = samples.last!
            XCTAssertLessThan(tracker.evidence(for: p, at: current)?.quietSeconds ?? 600, 600)
        }
    }
    func testStreamingEvidenceRejectsInvalidIntervalAndNonfiniteClock() {
        let p = process(cpu: 2)
        var tracker = ProcessEvidenceTracker()
        var sample = history(p, duration: 0)[0]
        tracker.update(sample)
        sample.monotonicTime = 0.05; sample.intervalSeconds = 0
        tracker.update(sample)
        XCTAssertEqual(tracker.evidence(for: p, at: sample)?.highCPUSeconds, 0)
        sample.monotonicTime = .nan
        tracker.update(sample)
        XCTAssertEqual(tracker.trackedProcessCount, 0)
        XCTAssertNil(tracker.evidence(for: p, at: sample))
    }
}
