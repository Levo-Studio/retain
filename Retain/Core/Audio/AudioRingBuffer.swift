import Foundation

/// Swift's side of `RetainRingBuffer`.
///
/// The type is a class and not a struct so that the C buffer has exactly one
/// owner and one deinit. It is `@unchecked Sendable` because the whole point is
/// that two threads touch it at once: the audio callback writes, the writer
/// queue reads, and the C implementation is what makes that safe. See
/// `RetainRingBuffer.h`.
///
/// One writer, one reader. Two of either corrupts it silently.
///
/// `nonisolated` because the project defaults types to the main actor and this
/// one is the opposite of a main-actor type: neither side of it ever runs
/// there.
nonisolated final class AudioRingBuffer: @unchecked Sendable {

    private let buffer: OpaquePointer

    /// - Parameter capacity: wanted size in bytes; the real one is rounded up
    ///   to a power of two and readable from `capacity`.
    init?(capacity: Int) {
        guard capacity > 0, let created = retain_ring_buffer_create(capacity) else { return nil }
        buffer = created
    }

    deinit {
        retain_ring_buffer_destroy(buffer)
    }

    var capacity: Int {
        retain_ring_buffer_capacity(buffer)
    }

    var available: Int {
        retain_ring_buffer_available(buffer)
    }

    /// Writes that were refused for want of space. Anything above zero means
    /// audio was lost, which is a defect rather than a condition to tolerate.
    var overruns: UInt64 {
        retain_ring_buffer_overruns(buffer)
    }

    // MARK: - Producer

    /// Copies a whole buffer of samples in. Producer side only.
    ///
    /// Returns false without writing anything if the space is short. Callers on
    /// the audio thread must not react to that with anything but a counter:
    /// there is nothing safe to do about it there.
    @discardableResult
    func write(_ samples: UnsafePointer<Float>, count: Int) -> Bool {
        samples.withMemoryRebound(to: UInt8.self, capacity: count * MemoryLayout<Float>.size) { bytes in
            retain_ring_buffer_write(buffer, bytes, count * MemoryLayout<Float>.size)
        }
    }

    // MARK: - Consumer

    /// Copies up to `count` samples out and returns how many it got. Consumer
    /// side only.
    func read(into destination: UnsafeMutablePointer<Float>, count: Int) -> Int {
        let bytes = destination.withMemoryRebound(to: UInt8.self, capacity: count * MemoryLayout<Float>.size) { raw in
            retain_ring_buffer_read(buffer, raw, count * MemoryLayout<Float>.size)
        }
        return bytes / MemoryLayout<Float>.size
    }

    /// Throws away everything readable. Consumer side, and only while the
    /// producer is stopped — the one caller is the format change, where the
    /// bytes still in here belong to a device that is gone.
    func reset() {
        retain_ring_buffer_reset(buffer)
    }
}
