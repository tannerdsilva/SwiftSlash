// LICENSE MIT
// copyright (c) tanner silva 2024. all rights reserved.
#ifndef _CSWIFTSLASH_FIFO_H
#define _CSWIFTSLASH_FIFO_H

#include "_cswiftslash_types.h"
#include <sys/types.h>
#include <pthread.h>

/// forward declaration of the fifo link structure. represents a single link in a sequential chain of data elements.
struct _cswiftslash_fifo_link;
/// defines a nullable pointer to a fifo link structure, allowing for the construction of linked chains.
typedef struct _cswiftslash_fifo_link* _Nullable _cswiftslash_fifo_link_ptr_t;
/// defines an atomic version of `_cswiftslash_fifo_link_ptr_t` to ensure thread-safe manipulation of the fifo links.
typedef _Atomic _cswiftslash_fifo_link_ptr_t _cswiftslash_fifo_link_aptr_t;
/// function prototype for consuming data from the chain. does not free the memory of the consumed pointer.
typedef void (^_Nonnull _cswiftslash_fifo_link_ptr_consume_f)(const _cswiftslash_ptr_t);

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
	_Atomic bool _is_capped;
	/// atomic pointer to the cap pointer, which is the final element in the chain.
	_Atomic _cswiftslash_optr_t _cap_ptr;
	
	/// mutex used to synchronize the state of various threads.
	pthread_mutex_t mutex;
} _cswiftslash_fifo_linkpair_t;

/// defines a non-null pointer to a fifo pair structure, facilitating operations on the entire chain.
typedef _cswiftslash_fifo_linkpair_t*_Nonnull _cswiftslash_fifo_linkpair_ptr_t;

// initialization and deinitialization

/// initializes a new fifo pair.
/// @return initialized fifo pair structure. NOTE: this structure must be closed with _cswiftslash_fifo_close to free all associated memory.
_cswiftslash_fifo_linkpair_t _cswiftslash_fifo_init();

/// deinitializes a fifo.
/// @param chain pointer to the fifo to be deinitialized.
/// @param deallocator_f function used for deallocating memory of data pointers.
/// @return the cap pointer if the chain was capped; NULL if the chain was not capped. the caller is responsible for freeing this pointer from memory.
_cswiftslash_optr_t _cswiftslash_fifo_close(const _cswiftslash_fifo_linkpair_ptr_t chain, const _cswiftslash_fifo_link_ptr_consume_f deallocator_f);

// data handling

/// cap off the fifo with a final element. any elements passed into the chain after capping it off will be stored and handled by the deallocator when this instance is closed (they will not be passed to a consumer).
/// @param chain pointer to the fifo to be capped.
/// @param ptr pointer to the final element to be added to the chain.
/// @return true if the cap pointer was successfully added; false if the cap could not be added.
bool _cswiftslash_fifo_pass_cap(const _cswiftslash_fifo_linkpair_ptr_t chain, const _cswiftslash_optr_t ptr);

/// inserts a new data pointer into the chain for storage and future processing. if the chain is capped, the data will be stored and handled by the deallocator when this instance is closed (it will not be passed to a consumer).
/// @param chain pointer to the fifo where data will be inserted.
/// @param ptr data pointer to be stored in the chain.
/// @return 0 on success. 1 when a retry should be done on the function call. -1 when the fifo is capped and no retry is necessary.
int8_t _cswiftslash_fifo_pass(const _cswiftslash_fifo_linkpair_ptr_t chain, const _cswiftslash_ptr_t ptr);

/// returns the next item in the chain. if no items are remaining and the chain is capped, the cap pointer will be returned (not for consumption, leave in memory). if no items are remaining and the chain is not capped, the function will block until an item is available (if specified by argument).
/// @param chain pointer to the fifo to consume from.
/// @param consumed_ptr pointer to the consumed data pointer, if any.
/// @return 0 if the function was successful and `consumed_ptr` was assigned to the next fifo entry to consume (consider this the last time you'll see this pointer - deallocate apropriately); -1 if the function would block. -2 if there was an internal error.
int8_t _cswiftslash_fifo_consume_nonblocking(const _cswiftslash_fifo_linkpair_ptr_t chain, _cswiftslash_optr_t*_Nonnull consumed_ptr);

#endif // _CSWIFTSLASH_FIFO_H