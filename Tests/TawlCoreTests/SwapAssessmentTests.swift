import XCTest
@testable import TawlCore

final class SwapAssessmentTests: XCTestCase {
    func snapshot(_ time: Double = 0, stock: UInt64? = 20_000_000_000,
                  incoming: Double? = 0, outgoing: Double? = 0,
                  pressure: Pressure = .normal) -> Snapshot {
        var sample = Snapshot(monotonicTime: time)
        sample.intervalSeconds = 2; sample.swapUsedBytes = stock
        sample.swapInBytesPerSecond = incoming; sample.swapOutBytesPerSecond = outgoing
        sample.pressure = pressure
        return sample
    }

    func testHighAccumulatedSwapAloneIsNotAnActiveBottleneck() {
        let result = assessSwap(snapshot: snapshot())
        XCTAssertEqual(result.activity, .idle)
        XCTAssertFalse(result.shouldReviewMemory)
        XCTAssertTrue(result.action.contains("işlem gerekmez"))
        XCTAssertNil(result.stockDeltaBytes)
    }

    func testDirectionAndPressureAreIndependent() {
        let writing = assessSwap(snapshot: snapshot(incoming: 100, outgoing: 200))
        XCTAssertEqual(writing.activity, .writing)
        XCTAssertTrue(writing.shouldReviewMemory)
        let reading = assessSwap(snapshot: snapshot(incoming: 100, outgoing: 0))
        XCTAssertEqual(reading.activity, .reading)
        XCTAssertFalse(reading.shouldReviewMemory)
        let idlePressure = assessSwap(snapshot: snapshot(pressure: .critical))
        XCTAssertEqual(idlePressure.activity, .idle)
        XCTAssertTrue(idlePressure.shouldReviewMemory)
        XCTAssertTrue(idlePressure.summary.contains("yine de"))
    }

    func testMissingInvalidAndPartialRatesNeverMeanIdle() {
        for invalid: Double? in [nil, .nan, .infinity, -1] {
            XCTAssertEqual(assessSwap(snapshot: snapshot(incoming: invalid)).activity, .unknown)
            XCTAssertEqual(assessSwap(snapshot: snapshot(outgoing: invalid)).activity, .unknown)
        }
        XCTAssertEqual(assessSwap(snapshot: snapshot(incoming: nil, outgoing: 100)).activity, .writing)
        XCTAssertEqual(assessSwap(snapshot: snapshot(incoming: 100, outgoing: nil)).activity, .reading)
        XCTAssertFalse(assessSwap(snapshot: snapshot(incoming: 100, outgoing: nil)).action.contains("yazma yoksa"))
        XCTAssertFalse(assessSwap(snapshot: snapshot(pressure: .unknown)).action.contains("işlem gerekmez"))
    }

    func testObservedStockChangeIsSignedAndUsesOnlyHistoryAtThisFrame() {
        let samples = [snapshot(0, stock: 1000), snapshot(2, stock: 1200), snapshot(4, stock: 800), snapshot(6, stock: 9000)]
        let result = assessSwap(snapshot: samples[2], history: samples)
        XCTAssertEqual(result.stockDeltaBytes, -200)
        XCTAssertEqual(result.observedSeconds, 4)
        let rising = assessSwap(snapshot: samples[1], history: samples)
        XCTAssertEqual(rising.stockDeltaBytes, 200)
        XCTAssertEqual(rising.observedSeconds, 2)
    }

    func testStockChangeStopsAtGapsAndMissingDataAndIsBounded() {
        var samples = [snapshot(0, stock: 1000), snapshot(2, stock: nil), snapshot(4, stock: 800)]
        XCTAssertNil(assessSwap(snapshot: samples[2], history: samples).stockDeltaBytes)
        samples = [snapshot(0, stock: 1000), snapshot(40, stock: 800)]
        XCTAssertNil(assessSwap(snapshot: samples[1], history: samples).stockDeltaBytes)
        samples = stride(from: 0, through: 240, by: 2).map { snapshot(Double($0), stock: UInt64($0)) }
        XCTAssertEqual(assessSwap(snapshot: samples.last!, history: samples).observedSeconds, 120)
        XCTAssertEqual(assessSwap(snapshot: samples.last!, history: samples).stockDeltaBytes, 120)
        var current = snapshot(2, stock: UInt64.max)
        XCTAssertNil(assessSwap(snapshot: current, history: [snapshot(0, stock: 0)]).stockDeltaBytes)
        current.intervalSeconds = .nan
        XCTAssertNil(assessSwap(snapshot: current, history: [snapshot(0, stock: UInt64.max)]).observedSeconds)
    }

    func testAdviceDoesNotAttributeSwapOrPromiseReclaimedMemory() {
        let result = assessSwap(snapshot: snapshot(outgoing: 100, pressure: .warning))
        XCTAssertTrue(result.limitation.contains("Süreç başına swap ölçülmüyor"))
        XCTAssertTrue(result.limitation.contains("kesin hesaplanamaz"))
        XCTAssertTrue(result.action.contains("normal kapat"))
        XCTAssertTrue(result.action.contains("karşılaştır"))
        XCTAssertFalse(result.action.lowercased().contains("sudo"))
    }
}
