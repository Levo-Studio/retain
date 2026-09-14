#include "RetainRingBuffer.h"

#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

struct RetainRingBuffer {
    uint8_t *bytes;
    size_t capacity;  // always a power of two
    size_t mask;      // capacity - 1

    // Monotonically increasing byte counters rather than wrapped indices. The
    // difference between them is the fill level directly, with no ambiguity
    // between "empty" and "full" that two wrapped indices would have, and they
    // do not overflow in any plausible lifetime: at 48 kHz stereo float, 2^64
    // bytes is about fifty million years of recording.
    _Atomic uint64_t written;
    _Atomic uint64_t read;

    _Atomic uint64_t overruns;
};

static size_t round_up_to_power_of_two(size_t value) {
    size_t result = 1;
    while (result < value) {
        size_t next = result << 1;
        if (next < result) {  // overflowed
            return result;
        }
        result = next;
    }
    return result;
}

RetainRingBuffer *retain_ring_buffer_create(size_t capacity) {
    if (capacity == 0) {
        return NULL;
    }

    RetainRingBuffer *buffer = calloc(1, sizeof(RetainRingBuffer));
    if (buffer == NULL) {
        return NULL;
    }

    buffer->capacity = round_up_to_power_of_two(capacity);
    buffer->mask = buffer->capacity - 1;
    buffer->bytes = malloc(buffer->capacity);
    if (buffer->bytes == NULL) {
        free(buffer);
        return NULL;
    }

    atomic_init(&buffer->written, 0);
    atomic_init(&buffer->read, 0);
    atomic_init(&buffer->overruns, 0);
    return buffer;
}

void retain_ring_buffer_destroy(RetainRingBuffer *buffer) {
    if (buffer == NULL) {
        return;
    }
    free(buffer->bytes);
    free(buffer);
}

size_t retain_ring_buffer_capacity(const RetainRingBuffer *buffer) {
    return buffer == NULL ? 0 : buffer->capacity;
}

uint64_t retain_ring_buffer_overruns(const RetainRingBuffer *buffer) {
    if (buffer == NULL) {
        return 0;
    }
    return atomic_load_explicit(&buffer->overruns, memory_order_relaxed);
}

size_t retain_ring_buffer_available(const RetainRingBuffer *buffer) {
    if (buffer == NULL) {
        return 0;
    }
    uint64_t written = atomic_load_explicit(&buffer->written, memory_order_acquire);
    uint64_t read = atomic_load_explicit(&buffer->read, memory_order_relaxed);
    return (size_t)(written - read);
}

bool retain_ring_buffer_write(RetainRingBuffer *buffer, const void *bytes, size_t count) {
    if (buffer == NULL || bytes == NULL) {
        return false;
    }
    if (count == 0) {
        return true;
    }

    // The producer owns `written`, so it can read its own counter relaxed. It
    // has to acquire `read` so that the consumer's advance is visible before
    // this thread decides the space is free to overwrite.
    uint64_t written = atomic_load_explicit(&buffer->written, memory_order_relaxed);
    uint64_t read = atomic_load_explicit(&buffer->read, memory_order_acquire);

    size_t free_space = buffer->capacity - (size_t)(written - read);
    if (free_space < count) {
        atomic_fetch_add_explicit(&buffer->overruns, 1, memory_order_relaxed);
        return false;
    }

    size_t offset = (size_t)(written & buffer->mask);
    size_t first = buffer->capacity - offset;
    if (first > count) {
        first = count;
    }
    memcpy(buffer->bytes + offset, bytes, first);
    if (count > first) {
        memcpy(buffer->bytes, (const uint8_t *)bytes + first, count - first);
    }

    // Release so the bytes above are visible to the consumer before the counter
    // that lets it read them.
    atomic_store_explicit(&buffer->written, written + count, memory_order_release);
    return true;
}

size_t retain_ring_buffer_read(RetainRingBuffer *buffer, void *destination, size_t count) {
    if (buffer == NULL || destination == NULL || count == 0) {
        return 0;
    }

    uint64_t read = atomic_load_explicit(&buffer->read, memory_order_relaxed);
    uint64_t written = atomic_load_explicit(&buffer->written, memory_order_acquire);

    size_t available = (size_t)(written - read);
    if (available == 0) {
        return 0;
    }
    if (count > available) {
        count = available;
    }

    size_t offset = (size_t)(read & buffer->mask);
    size_t first = buffer->capacity - offset;
    if (first > count) {
        first = count;
    }
    memcpy(destination, buffer->bytes + offset, first);
    if (count > first) {
        memcpy((uint8_t *)destination + first, buffer->bytes, count - first);
    }

    atomic_store_explicit(&buffer->read, read + count, memory_order_release);
    return count;
}

void retain_ring_buffer_reset(RetainRingBuffer *buffer) {
    if (buffer == NULL) {
        return;
    }
    uint64_t written = atomic_load_explicit(&buffer->written, memory_order_acquire);
    atomic_store_explicit(&buffer->read, written, memory_order_release);
}
