import XCTest
import Darwin
import IOKit
import CTawl
@testable import TawlCore

final class CollectorTests: XCTestCase {
    // An empty sampler, wrong PID identity, or zero-filled inaccessible metrics must fail.
    func testCollectIncludesOwnLifetimeAndReadableCounters() throws {
        let reading = NativeCollector().collect()
        let own = try XCTUnwrap(reading.processes.first { $0.pid == getpid() })
        XCTAssertGreaterThan(own.startedAt, 0)
        XCTAssertEqual(own.parentPID, getppid())
        XCTAssertFalse(own.name.isEmpty)
        XCTAssertNotNil(own.executablePath)
        XCTAssertGreaterThan(try XCTUnwrap(own.cpuNanoseconds), 0)
        XCTAssertGreaterThan(try XCTUnwrap(own.footprintBytes), 0)
        XCTAssertGreaterThan(try XCTUnwrap(own.residentBytes), 0)
        XCTAssertLessThanOrEqual(try XCTUnwrap(own.footprintBytes), reading.memoryTotalBytes)
        XCTAssertEqual(Set(reading.processes.map(\.id)).count, reading.processes.count)
        XCTAssertEqual(reading.processes.count + reading.unreadableProcessCount, reading.totalProcessCount)
    }

    // Missing host collection or bytes/ticks unit errors must fail without assuming a load level.
    func testCollectReportsSaneSystemCounters() throws {
        let reading = NativeCollector().collect()
        XCTAssertGreaterThan(reading.monotonicTime, 0)
        XCTAssertLessThan(abs(reading.timestamp.timeIntervalSinceNow), 10)
        XCTAssertGreaterThan(reading.logicalCPUCount, 0)
        XCTAssertGreaterThan(reading.memoryTotalBytes, 1_000_000_000)
        let ticks = try XCTUnwrap(reading.cpuTicks)
        XCTAssertGreaterThan(ticks.total, 0)
        XCTAssertLessThanOrEqual(ticks.busy, ticks.total)
        XCTAssertLessThanOrEqual(try XCTUnwrap(reading.compressedBytes), reading.memoryTotalBytes)
        XCTAssertNotNil(reading.swapUsedBytes)
        XCTAssertNotNil(reading.swapInBytes)
        XCTAssertNotNil(reading.swapOutBytes)
        XCTAssertNotNil(reading.networkInBytes)
        XCTAssertNotNil(reading.networkOutBytes)
    }

    // Sampling must preserve PID lifetime and produce cumulative CPU rather than per-call rates.
    func testRepeatedCollectionPreservesOwnLifetimeAndMonotonicCPU() throws {
        let collector = NativeCollector()
        let first = collector.collect()
        let firstOwn = try XCTUnwrap(first.processes.first { $0.pid == getpid() })
        Thread.sleep(forTimeInterval: 0.03)
        let second = collector.collect()
        let secondOwn = try XCTUnwrap(second.processes.first { $0.pid == getpid() })
        XCTAssertEqual(firstOwn.id, secondOwn.id)
        XCTAssertGreaterThan(second.monotonicTime, first.monotonicTime)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(secondOwn.cpuNanoseconds), try XCTUnwrap(firstOwn.cpuNanoseconds))
    }

    // A Mach-tick/nanosecond conversion error would disagree with getrusage's independent CPU clock.
    func testOwnCPUIsReportedInNanoseconds() throws {
        func cpuTime() throws -> UInt64 {
            var usage = rusage()
            XCTAssertEqual(getrusage(RUSAGE_SELF, &usage), 0)
            return UInt64(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) * 1_000_000_000
                + UInt64(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) * 1_000
        }
        let before = try cpuTime()
        let own = try XCTUnwrap(NativeCollector().collect().processes.first { $0.pid == getpid() })
        let after = try cpuTime()
        let reported = try XCTUnwrap(own.cpuNanoseconds)
        XCTAssertGreaterThanOrEqual(reported + 30_000_000, before)
        XCTAssertLessThanOrEqual(reported, after + 30_000_000)
    }

    // Counting mounted disk-image drivers alongside their backing device doubles storage work.
    func testSystemDiskCountersExcludeMountedDiskImages() throws {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else {
            throw XCTSkip("IOKit registry is inaccessible on this host")
        }
        defer { IOObjectRelease(iterator) }
        var totalDrivers = 0, imageDrivers = 0
        while true {
            let driver = IOIteratorNext(iterator)
            if driver == 0 { break }
            totalDrivers += 1
            var parent: io_registry_entry_t = 0
            if IORegistryEntryGetParentEntry(driver, kIOServicePlane, &parent) == KERN_SUCCESS {
                if IOObjectConformsTo(parent, "AppleDiskImageDevice") != 0 { imageDrivers += 1 }
                IOObjectRelease(parent)
            }
            IOObjectRelease(driver)
        }
        guard imageDrivers > 0 else { throw XCTSkip("No mounted disk-image drivers to exercise exclusion") }
        let reading = try XCTUnwrap(nb_collect())
        defer { nb_free_reading(reading) }
        XCTAssertGreaterThan(reading.pointee.disk_driver_count, 0)
        XCTAssertLessThanOrEqual(Int(reading.pointee.disk_driver_count), totalDrivers - imageDrivers)
    }
}
