//  A single-producer, single-consumer lock-free ring buffer.
//
//  This is C rather than Swift on purpose, and it is the one piece of C in
//  Retain. The producer is an audio callback, where hard rule 5 allows a memcpy
//  and a timestamp and nothing else — no allocation, no lock, no logging, no
//  Swift runtime call that might do any of the three behind your back. Written
//  in C against <stdatomic.h> that property is readable straight off the page
//  and cannot regress by accident.
//
//  It would have been Swift if the deployment target allowed it: the
//  Synchronization module's Atomic is macOS 15, Retain targets macOS 14, and
//  every workaround inside the language is either a lock (forbidden here) or a
//  sixth dependency. Eighty lines of C is the smaller price.
//
//  Exactly one thread may write and exactly one thread may read. Two writers or
//  two readers corrupt it silently; there is no check for that, because a check
//  in the write path would cost more than it is worth.

#ifndef RETAIN_RING_BUFFER_H
#define RETAIN_RING_BUFFER_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct RetainRingBuffer RetainRingBuffer;

/// Allocates a buffer able to hold at least `capacity` bytes. The real capacity
/// is rounded up to a power of two so the index wrap is a mask rather than a
/// division. Returns NULL if the allocation fails or `capacity` is zero.
///
/// Call this off the audio thread. It allocates.
RetainRingBuffer *retain_ring_buffer_create(size_t capacity);

/// Frees the buffer. Neither side may touch it afterwards.
void retain_ring_buffer_destroy(RetainRingBuffer *buffer);

/// The rounded-up capacity in bytes.
size_t retain_ring_buffer_capacity(const RetainRingBuffer *buffer);

/// Copies `count` bytes in. Producer side only.
///
/// All or nothing: if the free space is smaller than `count` nothing is written,
/// the overrun counter goes up by one, and the call returns false. Partially
/// writing a block would tear a run of audio frames in a way the consumer could
/// not detect.
///
/// Never blocks and never allocates.
bool retain_ring_buffer_write(RetainRingBuffer *buffer, const void *bytes, size_t count);

/// Copies out at most `count` bytes and returns how many it got. Consumer side
/// only. Never blocks.
size_t retain_ring_buffer_read(RetainRingBuffer *buffer, void *destination, size_t count);

/// Bytes currently readable. A snapshot: the producer may have added more by
/// the time the caller looks at the answer, never fewer.
size_t retain_ring_buffer_available(const RetainRingBuffer *buffer);

/// How many writes have been refused for want of space since the buffer was
/// created. Anything but zero means audio was lost and the consumer is not
/// keeping up.
uint64_t retain_ring_buffer_overruns(const RetainRingBuffer *buffer);

/// Drops everything readable. Consumer side only, and only while the producer
/// is stopped — used when the input format changes and the bytes still in the
/// buffer belong to the old one.
void retain_ring_buffer_reset(RetainRingBuffer *buffer);

#endif /* RETAIN_RING_BUFFER_H */
