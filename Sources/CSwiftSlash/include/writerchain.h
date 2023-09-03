#ifndef CLIBSWIFTSLASH_WC_H
#define CLIBSWIFTSLASH_WC_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

/// a pointer to an integer, an integer which signifies error codes.
typedef int*_Nonnull err_ptr_t;

/// a pointer to an unsigned integer, an integer which signifies a count of successful operations.
typedef uint32_t*_Nonnull succ_ptr_t;

/// a pointer to a data byte buffer.
typedef uint8_t*_Nonnull data_ptr_t;

// forward declaration of the writerchain structure.
struct writerchain;

/// a pointer to a writerchain structure.
typedef struct writerchain* _Nullable writerchain_ptr_t;

/// an atomic ``writerchain_ptr_t``.
typedef _Atomic writerchain_ptr_t writerchain_aptr_t;

/// a pointer to a ``writerchain_aptr_t``.
typedef writerchain_aptr_t* _Nonnull writerchain_aptr_ptr_t;

/// primary writer chain link item.
typedef struct writerchain {
    const data_ptr_t data;
    const size_t datasize;
    _Atomic size_t written;
    writerchain_aptr_t next;
} writerchain_t;

/// @param base the pointer to a chain to append to. the pointed to value may be NULL, and this is how a new chain is created.
/// @param tail the tail of the chain to append to. the pointed to value may be NULL, and this is how a new chain is created.
/// @param data the data to append.
/// @param datalen the length of the data to append.
void wc_append(const writerchain_aptr_ptr_t base, const writerchain_aptr_ptr_t tail, const data_ptr_t data, const size_t datalen);

/// @brief flushes as much of the chain to the file handle as possible
/// @param base the pointer to the base of the chain to flush.
/// @param tail the tail of the chain to flush.
/// @param fd the file handle to flush to
/// @param err the error code to set if an error occurs
/// @return boolean indicating whether there was a critical error.
bool wc_flush(const writerchain_aptr_ptr_t base, const writerchain_aptr_ptr_t tail, const int fd, const err_ptr_t err);

/// @brief deinitialize a given writerchain
/// @param base the chain to deinitialize
void wc_close(const writerchain_aptr_ptr_t base, const writerchain_aptr_ptr_t tail);

#endif /* CLIBSWIFTSLASH_WC_H */
