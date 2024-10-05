// LICENSE MIT
// copyright (c) tanner silva 2024. all rights reserved.
#ifndef _CSWIFTSLASH_FIFO_H
#define _CSWIFTSLASH_FIFO_H

#include "__cswiftslash_types.h"
#include <sys/types.h>
#include <pthread.h>

/// forward declaration of the fifo link structure. represents a single link in a sequential chain of data elements.
struct _cswiftslash_fifo_link;
/// defines a nullable pointer to a fifo link structure, allowing for the construction of linked chains.
typedef struct _cswiftslash_fifo_link* _Nullable _cswiftslash_fifo_link_ptr_t;
/// defines an atomic version of `_cswiftslash_fifo_link_ptr_t` to ensure thread-safe manipulation of the fifo links.
typedef _Atomic _cswiftslash_fifo_link_ptr_t _cswiftslash_fifo_link_aptr_t;
/// function prototype for consuming data from the chain.
typedef void (* _cswiftslash_fifo_link_ptr_consume_f)(const _cswiftslash_ptr_t);

// fifo consumption results.
typedef enum fifo_consume_result {
	// pending status (future not fufilled)
	FIFO_CONSUME_RESULT = 0,
	// result status (future fufilled normally)
	FIFO_CONSUME_CAP = 1,
	// thrown status (future fufilled with an error)
	FIFO_CONSUME_WOULDBLOCK = 2,
	// cancel status (future was not fufilled and will NOT fufill in the future)
	FIFO_CONSUME_INTERNAL_ERROR = 3,
} _cswiftslash_fifo_consume_result_t;

/// structure representing a single link within the fifo, holding a data item and a pointer to the next chain item.
typedef struct _cswiftslash_fifo_link {
	/// the data item held by this link in the chain.
	const _cswiftslash_ptr_t ptr;
	/// pointer to the next item in the chain, facilitating the link structure.
	_cswiftslash_fifo_link_aptr_t next;
} _cswiftslash_fifo_link_t;

/// structure representing a pair of pointers to the head and tail of a fifo, enabling efficient management and access to both ends of the chain.
typedef struct _cswiftslash_fifo_linkpair {
	/// pointer to the base (head) of the chain, serving as the entry point.
	_cswiftslash_fifo_link_aptr_t base;
	/// pointer to the tail of the chain, enabling efficient addition of new elements.
	_cswiftslash_fifo_link_aptr_t tail;
	
	/// atomic counter representing the number of elements in the chain.
	_Atomic uint64_t element_count;

	/// atomic boolean flag indicating whether blocking is enabled on the chain.
	_Atomic bool is_capped;
	/// atomic pointer to the cap pointer, which is the final element in the chain.
	_Atomic _cswiftslash_optr_t cap_ptr;
	
	/// mutex used to synchronize the internal state of the fifo. this is optional because there may be parent structures that are synchronized in the same way, therefore, can opt out of the built in synchronization to eliminate overhead.
	bool has_mutex;
	pthread_mutex_t mutex_optional;

	/// mutex used to signal to waiting threads when a result is available again. one may argue that there are better pthread primitives to use for this, but the swift runtime only wants to operate with mutexes.
	_Atomic bool is_waiters_mutex_locked;
	pthread_mutex_t waiters_mutex;

	/// maximum number of elements that can be stored in the chain.
	_Atomic bool has_max_elements;
	_Atomic size_t max_elements;
} _cswiftslash_fifo_linkpair_t;

/// defines a non-null pointer to a fifo pair structure, facilitating operations on the entire chain.
typedef _cswiftslash_fifo_linkpair_t*_Nonnull _cswiftslash_fifo_linkpair_ptr_t;

// initialization and deinitialization

/// @brief initializes a new mutex for use with a fifo chain. this is a convenience function that wraps the pthread_mutex_init function.
/// @return a newly initialized mutex that can be passed directly into the fifo initializer.
pthread_mutex_t _cswiftslash_fifo_mutex_new();

/// @brief initializes a new fifo pair. if this fifo is used as an independent concurrency unit, the mutex should be initialized and passed in. when a newly initialized mutex is passed in the initializer, it will automatically be destroyed at the apropriate time (pass and forget). a mutex is not required if the fifo is used in a single-threaded context.
/// @return initialized fifo pair structure. NOTE: this structure must be closed with _cswiftslash_fifo_close to free all associated memory.
_cswiftslash_fifo_linkpair_t _cswiftslash_fifo_init(pthread_mutex_t *_Nullable mutex);

/// @brief sets the maximum number of elements that can be buffered by the fifo if there is not a consumer immediately available.
/// @param chain pointer to the fifo to be capped.
/// @param max_elements maximum number of elements that can be stored in the chain.
/// @return true if the max elements was successfully set; false if the max elements could not be set.
bool _cswiftslash_fifo_set_max_elements(const _cswiftslash_fifo_linkpair_ptr_t chain, const size_t max_elements);

/// @brief deinitializes a fifo.
/// @param chain pointer to the fifo to be deinitialized.
/// @param deallocator_f function used for deallocating memory of data pointers.
/// @return the cap pointer if the chain was capped; NULL if the chain was not capped. the caller is responsible for freeing this pointer from memory.
_cswiftslash_optr_t _cswiftslash_fifo_close(const _cswiftslash_fifo_linkpair_ptr_t chain, const _cswiftslash_fifo_link_ptr_consume_f _Nullable deallocator_f);

// data handling

/// @brief cap off the fifo with a final element. any elements passed into the chain after capping it off will be stored and handled by the deallocator when this instance is closed (they will not be passed to a consumer).
/// @param chain pointer to the fifo to be capped.
/// @param ptr pointer to the final element to be added to the chain.
/// @return true if the cap pointer was successfully added; false if the cap could not be added.
bool _cswiftslash_fifo_pass_cap(const _cswiftslash_fifo_linkpair_ptr_t chain, const _cswiftslash_optr_t ptr);

/// @brief inserts a new data pointer into the chain for storage and future processing. if the chain is capped, the data will be stored and handled by the deallocator when this instance is closed (it will not be passed to a consumer).
/// @param chain pointer to the fifo where data will be inserted.
/// @param ptr data pointer to be stored in the chain.
/// @return 0 on success. 1 when a retry should be done on the function call. -1 when the fifo is capped and no retry is necessary. -2 will be returned if the maximum number of elements has been reached.
int8_t _cswiftslash_fifo_pass(const _cswiftslash_fifo_linkpair_ptr_t chain, const _cswiftslash_ptr_t ptr);

/// @brief consumes the next data pointer in the chain, removing it from the chain and returning it to the caller. if the chain is empty, the function will return immediately with the apropriate return status indicating that the chain is empty.
_cswiftslash_fifo_consume_result_t _cswiftslash_fifo_consume_nonblocking(const _cswiftslash_fifo_linkpair_ptr_t chain, _cswiftslash_optr_t*_Nonnull consumed_ptr);

/// @brief consumes the next data pointer in the chain, removing it from the chain and returning it to the caller. if the chain is empty, the function will block until a new element is added to the chain.
_cswiftslash_fifo_consume_result_t _cswiftslash_fifo_consume_blocking(const _cswiftslash_fifo_linkpair_ptr_t chain, _cswiftslash_optr_t*_Nonnull consumed_ptr);

#endif // _CSWIFTSLASH_FIFO_H