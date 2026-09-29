import Foundation
import XCTest
@testable import Louppe

final class AudioCancellationTests: XCTestCase {
    func testLastWaiterCancellationStopsRunningReaderAndRerequestWaitsForItsExit() async throws {
        let gate = AudioDecodeGate()
        let pipeline = AudioLevelPipeline { _, _, cancelled in
            let call = gate.begin()
            defer { gate.end() }
            if call == 1 {
                gate.firstStarted.signal()
                while !cancelled(), !gate.timedOut { Thread.sleep(forTimeInterval: 0.001) }
                gate.cancellationObserved.signal()
                _ = gate.releaseFirst.wait(timeout: .now() + 5)
                // Intentionally return partial data after cancellation; it must
                // never reach a new same-revision waiter or the result cache.
                return AudioLevelProcessor.analyze(channels: [[0.1]], binCount: 1)
            }
            gate.secondStarted.signal()
            return AudioLevelProcessor.analyze(channels: [[0.9]], binCount: 1)
        }
        let item = makeAudioItem("same-key")
        let abandoned = Task { await pipeline.analysis(for: item) }
        let started = await wait(gate.firstStarted)
        XCTAssertEqual(started, .success)
        abandoned.cancel()
        let cancelled = await abandoned.value
        XCTAssertNil(cancelled)
        let observed = await wait(gate.cancellationObserved)
        XCTAssertEqual(observed, .success)
        let renewed = Task { await pipeline.analysis(for: item) }
        let prematurelyStarted = await Task.detached {
            blockingAudioWait(gate.secondStarted, timeout: .now() + 0.08)
        }.value
        XCTAssertEqual(prematurelyStarted, .timedOut, "the serial slot must stay owned until the reader exits")
        gate.releaseFirst.signal()
        let result = await renewed.value
        XCTAssertEqual(result?.channels.first?.peak, 0.9)
        XCTAssertEqual(gate.maximumConcurrent, 1)
        XCTAssertEqual(gate.calls, 2)
        let cached = await pipeline.analysis(for: item)
        XCTAssertEqual(cached?.channels.first?.peak, 0.9)
        XCTAssertEqual(gate.calls, 2, "only the renewed complete result may be cached")
    }

    func testCancellingOneCoalescedWaiterKeepsTheSurvivingReader() async throws {
        let gate = AudioDecodeGate()
        let pipeline = AudioLevelPipeline { _, _, cancelled in
            _ = gate.begin()
            defer { gate.end() }
            gate.firstStarted.signal()
            _ = gate.releaseFirst.wait(timeout: .now() + 5)
            if cancelled() { gate.cancellationObserved.signal(); return nil }
            return AudioLevelProcessor.analyze(channels: [[0.5]], binCount: 1)
        }
        let item = makeAudioItem("coalesced")
        let first = Task { await pipeline.analysis(for: item) }
        let started = await wait(gate.firstStarted)
        XCTAssertEqual(started, .success)
        let surviving = Task { await pipeline.analysis(for: item) }
        try await Task.sleep(for: .milliseconds(50))
        first.cancel()
        let firstResult = await first.value
        XCTAssertNil(firstResult)
        gate.releaseFirst.signal()
        let survivingResult = await surviving.value
        XCTAssertEqual(survivingResult?.channels.first?.peak, 0.5)
        XCTAssertEqual(gate.calls, 1)
        XCTAssertEqual(blockingAudioWait(gate.cancellationObserved, timeout: .now()), .timedOut)
    }

    private func wait(_ semaphore: DispatchSemaphore) async -> DispatchTimeoutResult {
        await Task.detached { blockingAudioWait(semaphore, timeout: .now() + 5) }.value
    }

    private func makeAudioItem(_ id: String) -> PhotoItem {
        PhotoItem(id: id, primaryURL: URL(fileURLWithPath: "/private/tmp/\(UUID())/\(id).wav"),
            pairedURL: nil, captureDate: nil, cameraModel: nil, lensModel: nil,
            mediaKind: .audio, duration: 1, audioIsPlayable: true, fileSize: 1)
    }
}

private final class AudioDecodeGate: @unchecked Sendable {
    let firstStarted = DispatchSemaphore(value: 0)
    let secondStarted = DispatchSemaphore(value: 0)
    let cancellationObserved = DispatchSemaphore(value: 0)
    let releaseFirst = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var active = 0
    private var maximum = 0
    private var count = 0
    private let deadline = Date().addingTimeInterval(5)
    var timedOut: Bool { Date() >= deadline }
    var calls: Int { lock.withLock { count } }
    var maximumConcurrent: Int { lock.withLock { maximum } }
    func begin() -> Int {
        lock.withLock { count += 1; active += 1; maximum = max(maximum, active); return count }
    }
    func end() { lock.withLock { active -= 1 } }
}

private func blockingAudioWait(_ semaphore: DispatchSemaphore, timeout: DispatchTime) -> DispatchTimeoutResult {
    semaphore.wait(timeout: timeout)
}
