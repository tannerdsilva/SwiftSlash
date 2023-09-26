#ifndef CLIBSWIFTSLASH_WC_H
#define CLIBSWIFTSLASH_WC_H

#include <stddef.h>
#include <pthread.h>

#include "future.h"

#include "types.h"

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
	const bool futureInitialized;
	future_int64_t future;
} writerchain_t;

/// a structure that stores the base and tail of the writerchain.
typedef struct writerchainpair {
	writerchain_aptr_ptr_t base;
	writerchain_aptr_ptr_t tail;
} writerchainpair_t;

typedef writerchainpair_t*_Nonnull writerchainpair_ptr_t;

/// @brief initializes a writerchainpair
writerchainpair_t wcp_init(void);

/// @brief deinitializes a writerchainpair
void wcp_close(const writerchainpair_ptr_t chain);

/// @brief appends data to a writerchain.
/// @param base the pointer to a chain to append to. the pointed to value may be NULL, and this is how a new chain is created.
/// @param chain the chain to append the data to.
/// @param data the data to append to the chain.
/// @param datalen the length of the data to append.
void wc_append(const writerchainpair_ptr_t chain, const data_ptr_t data, const size_t datalen);

/// @brief appends data to a writerchain and returns a future that will be completed when the data is written.
/// @param chain the pointer to a chain to append to.
/// @param data the data to append to the chain.
/// @param datalen the length of the data to append.
future_int64_ptr_t wc_append_future(const writerchainpair_ptr_t chain, const data_ptr_t data, const size_t datalen);

/// @brief flushes as much of the chain to the file handle as possible.
/// @param chain the chain to flush.
/// @param fd the file handle to flush to.
/// @param err a pointer to an integer that will be set to the error code of the final write operation, if it failed.
/// @return boolean indicating whether the write operation was successful.
/// @note this function may assign a value for err even though it returns true.
bool wc_flush(const writerchainpair_ptr_t chain, const int fd, const err_ptr_t err);

#endif /* CLIBSWIFTSLASH_WC_H */
