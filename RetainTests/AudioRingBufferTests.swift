import Testing

@testable import Retain

/// The ring buffer is the one place in Retain where a bug costs audio that
/// cannot be recovered, and it is the one piece of C. Both make it worth
/// testing at the edges rather than down the middle.
@Suite("Audio ring buffer")
struct AudioRingBufferTests {

    /// Byte capacity for a given number of Float samples.
    private static func bytes(forSamples count: Int) -> Int {
        count * MemoryLayout<Float>.size
    }

    private func roundTrip(_ buffer: AudioRingBuffer, writing input: [Float], reading count: Int) -> [Float] {
        input.withUnsafeBufferPointer { source in
            _ = buffer.write(source.baseAddress!, count: input.count)
        }
        var output = [Float](repeating: .nan, count: count)
        let got = output.withUnsafeMutableBufferPointer { destination in
            buffer.read(into: destination.baseAddress!, count: count)
        }
        return Array(output.prefix(got))
    }

    @Test("Capacity rounds up to a power of two")
    func capacityRoundsUp() throws {
        let buffer = try #require(AudioRingBuffer(capacity: 1000))
        #expect(buffer.capacity == 1024)

        let exact = try #require(AudioRingBuffer(capacity: 4096))
        #expect(exact.capacity == 4096)
    }

    @Test("A zero capacity is refused rather than rounded to one")
    func zeroCapacityIsRefused() {
        #expect(AudioRingBuffer(capacity: 0) == nil)
    }

    @Test("Samples come back in the order they went in")
    func preservesOrder() throws {
        let buffer = try #require(AudioRingBuffer(capacity: Self.bytes(forSamples: 64)))
        let input: [Float] = [0.1, -0.2, 0.3, -0.4, 0.5]
        #expect(roundTrip(buffer, writing: input, reading: input.count) == input)
    }

    @Test("Reading more than is there returns only what is there")
    func readsAtMostWhatIsAvailable() throws {
        let buffer = try #require(AudioRingBuffer(capacity: Self.bytes(forSamples: 64)))
        let input: [Float] = [1, 2, 3]
        #expect(roundTrip(buffer, writing: input, reading: 100) == input)
    }

    @Test("An empty buffer reads nothing rather than stale bytes")
    func emptyReadsNothing() throws {
        let buffer = try #require(AudioRingBuffer(capacity: Self.bytes(forSamples: 64)))
        var output = [Float](repeating: 7, count: 8)
        let got = output.withUnsafeMutableBufferPointer { buffer.read(into: $0.baseAddress!, count: 8) }
        #expect(got == 0)
        #expect(output == [Float](repeating: 7, count: 8))
    }

    /// The case a wrapped-index implementation gets wrong: writing past the end
    /// of the allocation so the block is split in two memcpys, and the same on
    /// the way out.
    @Test("A write that straddles the end of the allocation is not torn")
    func wrapsWithoutTearing() throws {
        let samples = 16
        let buffer = try #require(AudioRingBuffer(capacity: Self.bytes(forSamples: samples)))

        // Push the write cursor most of the way round, then write a block that
        // has to split.
        let filler = [Float](repeating: 0, count: samples - 3)
        #expect(roundTrip(buffer, writing: filler, reading: filler.count) == filler)

        let straddling: [Float] = [10, 20, 30, 40, 50, 60]
        #expect(roundTrip(buffer, writing: straddling, reading: straddling.count) == straddling)
    }

    @Test("Filling the buffer exactly is allowed, one more sample is not")
    func fillsToCapacity() throws {
        let samples = 8
        let buffer = try #require(AudioRingBuffer(capacity: Self.bytes(forSamples: samples)))

        let full = (0..<samples).map(Float.init)
        full.withUnsafeBufferPointer { #expect(buffer.write($0.baseAddress!, count: samples)) }
        #expect(buffer.available == Self.bytes(forSamples: samples))
        #expect(buffer.overruns == 0)

        var one: Float = 99
        #expect(buffer.write(&one, count: 1) == false)
        #expect(buffer.overruns == 1)
    }

    /// The behaviour that matters for a recording: a refused write leaves the
    /// existing audio alone. Overwriting the oldest samples would silently
    /// punch a hole in the middle of the lecture instead of at the end, and
    /// nothing downstream could tell.
    @Test("A refused write drops nothing that was already in")
    func overrunKeepsWhatIsAlreadyThere() throws {
        let samples = 8
        let buffer = try #require(AudioRingBuffer(capacity: Self.bytes(forSamples: samples)))

        let full = (0..<samples).map(Float.init)
        full.withUnsafeBufferPointer { _ = buffer.write($0.baseAddress!, count: samples) }

        var rejected: Float = -1
        #expect(buffer.write(&rejected, count: 1) == false)

        var output = [Float](repeating: .nan, count: samples)
        let got = output.withUnsafeMutableBufferPointer { buffer.read(into: $0.baseAddress!, count: samples) }
        #expect(got == samples)
        #expect(output == full)
    }

    @Test("A partial write is never made: all of the block or none of it")
    func writesAreAllOrNothing() throws {
        let samples = 8
        let buffer = try #require(AudioRingBuffer(capacity: Self.bytes(forSamples: samples)))

        let six: [Float] = [1, 2, 3, 4, 5, 6]
        six.withUnsafeBufferPointer { _ = buffer.write($0.baseAddress!, count: 6) }

        // Four more would need eight free; only two are.
        let four: [Float] = [7, 8, 9, 10]
        four.withUnsafeBufferPointer { #expect(buffer.write($0.baseAddress!, count: 4) == false) }

        #expect(buffer.available == Self.bytes(forSamples: 6))
        var output = [Float](repeating: .nan, count: 6)
        _ = output.withUnsafeMutableBufferPointer { buffer.read(into: $0.baseAddress!, count: 6) }
        #expect(output == six)
    }

    @Test("Reset throws away what is unread and frees the space")
    func resetDiscards() throws {
        let samples = 8
        let buffer = try #require(AudioRingBuffer(capacity: Self.bytes(forSamples: samples)))

        let full = (0..<samples).map(Float.init)
        full.withUnsafeBufferPointer { _ = buffer.write($0.baseAddress!, count: samples) }
        #expect(buffer.available == Self.bytes(forSamples: samples))

        buffer.reset()
        #expect(buffer.available == 0)

        let fresh: [Float] = [100, 200]
        #expect(roundTrip(buffer, writing: fresh, reading: fresh.count) == fresh)
    }

    /// Runs the producer and the consumer on two real threads for long enough
    /// to wrap the allocation many times over, and checks that what comes out
    /// is exactly the sequence that went in. A lock-free buffer that is subtly
    /// wrong passes every single-threaded test above.
    @Test("Concurrent producer and consumer lose and reorder nothing")
    func survivesTwoThreads() async throws {
        let samples = 256
        let buffer = try #require(AudioRingBuffer(capacity: Self.bytes(forSamples: samples)))
        let total = 200_000

        let producer = Task.detached(priority: .userInitiated) {
            var next = 0
            let block = 64
            while next < total {
                let count = min(block, total - next)
                var chunk = [Float](repeating: 0, count: count)
                for index in 0..<count { chunk[index] = Float(next + index) }
                let written = chunk.withUnsafeBufferPointer {
                    buffer.write($0.baseAddress!, count: count)
                }
                if written {
                    next += count
                }
                // No sleep and no lock: a full buffer means try again, which is
                // what the audio thread cannot do and the test can.
            }
        }

        let consumer = Task.detached(priority: .utility) { () -> Int in
            var expected = 0
            var scratch = [Float](repeating: 0, count: 64)
            while expected < total {
                let got = scratch.withUnsafeMutableBufferPointer {
                    buffer.read(into: $0.baseAddress!, count: 64)
                }
                for index in 0..<got {
                    if scratch[index] != Float(expected) { return expected }
                    expected += 1
                }
            }
            return expected
        }

        await producer.value
        let consumed = await consumer.value

        // The whole sequence, in order, with nothing repeated or skipped. The
        // consumer bails out at the first sample that is not the one it was
        // expecting, so a short count means the buffer reordered or lost data.
        #expect(consumed == total)

        // Overruns are expected here and are not a defect: this producer writes
        // as fast as it can and retries a refused write, which is exactly what
        // an audio callback may not do. What matters is that a refused write
        // cost nothing, which the count above proves.
    }
}
