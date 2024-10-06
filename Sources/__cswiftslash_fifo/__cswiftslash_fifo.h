/* LICENSE MIT
copyright (c) tanner silva 2024. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

#ifndef _CSWIFTSLASH_FIFO_H
#define _CSWIFTSLASH_FIFO_H

#include "__cswiftslash_types.h"

#include <sys/types.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>

/// @brief forward declaration of the fifo link structure. represents a single link (a single element) in a sequential chain of n number of elements. a foundational structure for the fifo mechanism.
struct _cswiftslash_fifo_link;

/// @brief a nullable pointer to a fifo link structure, allowing for the construction of chains of link elements.
typedef struct _cswiftslash_fifo_link *_Nullable _cswiftslash_fifo_link_ptr_t;

/// @brief defines an atomic version of `_cswiftslash_fifo_link_ptr_t` to ensure thread-safe manipulation of the fifo links.
typedef _Atomic _cswiftslash_fifo_link_ptr_t _cswiftslash_fifo_link_aptr_t;

/// @brief function prototype for consuming data from the chain.
typedef void (* _cswiftslash_fifo_link_ptr_consume_f)(const _cswiftslash_ptr_t);

/// @brief fifo consumption results.
typedef enum _cswiftslash_fifo_consume_result {

	/// @brief returned when a fifo element is consumed normally.
	FIFO_CONSUME_RESULT = 0,

	/// @brief returned when the fifo element is "capped off" and as such, there are no more elements to consume. cap pointer is returned with this result.
	FIFO_CONSUME_CAP = 1,

	/// @brief returned when the fifo element is empty and the consumer should block until a new element is added.
	FIFO_CONSUME_WOULDBLOCK = 2,

	/// @brief returned when an internal error occurs during the consumption process.
	FIFO_CONSUME_INTERNAL_ERROR = 3,

} _cswiftslash_fifo_consume_result_t;

/// @brief structure representing a single link within the fifo, stores a data item and a pointer to the next chain item.
typedef struct _cswiftslash_fifo_link {

	/// @brief the data item stored by this link in the chain.
	const _cswiftslash_ptr_t ptr;

	/// @brief pointer to the next item in the chain.
	_cswiftslash_fifo_link_aptr_t next;

} _cswiftslash_fifo_link_t;

/// @brief structure representing a pair of pointers to the head and tail of a fifo, enabling efficient management and access to both ends of the chain. stores an assortment of other metadata to facilitate efficient and safe operation of the fifo mechanism. NOTE: none of the fields in this structure need to be accessed directly by the caller.
typedef struct _cswiftslash_fifo_linkpair {

	/// @brief pointer to the base (head) of the chain, serving as the entry point.
	_cswiftslash_fifo_link_aptr_t base;
	/// @brief pointer to the tail of the chain, enabling efficient addition of new elements.
	_cswiftslash_fifo_link_aptr_t tail;
	
	/// @brief atomic counter representing the number of elements in the chain.
	_Atomic uint64_t element_count;

	/// @brief atomic boolean flag indicating whether blocking is enabled on the chain.
	_Atomic bool is_capped;
	/// @brief atomic pointer to the cap pointer, which is the final element in the chain.
	_Atomic _cswiftslash_optr_t cap_ptr;
	
	// mutex used to synchronize the internal state of the fifo. this is optional because there may be parent structures that are synchronized in the same way, therefore, can opt out of the built in synchronization to eliminate overhead.
	const bool has_mutex;
	pthread_mutex_t mutex_optional;

	/// mutex used to signal to waiting threads when a result is available again. one may argue that there are better pthread primitives to use for this, but the swift runtime only wants to operate with mutexes.
	_Atomic bool is_waiters_mutex_locked;
	pthread_mutex_t waiters_mutex;

	/// @brief atomic boolean flag indicating whether the chain is currently configured with a maximum number of elements.
	_Atomic bool has_max_elements;
	/// @brief atomic size_t representing the maximum number of elements that can be stored in the chain.
	_Atomic size_t max_elements;

} _cswiftslash_fifo_linkpair_t;

/// defines a non-null pointer to a fifo pair structure, facilitating operations on the entire chain.
typedef _cswiftslash_fifo_linkpair_t*_Nonnull _cswiftslash_fifo_linkpair_ptr_t;

// initialization, configuration and deinitialization

/// @brief initializes a new mutex for use with a fifo chain. this is a convenience function that wraps the pthread_mutex_init function.
/// @return a newly initialized mutex that can be passed directly into the fifo initializer.
pthread_mutex_t _cswiftslash_fifo_mutex_new();

/// @brief initializes a new fifo pair. if this fifo is used as an independent concurrency unit in your application, a mutex should be initialized (using `_cswiftslash_fifo_mutex_new`) and passed in here. when a newly initialized mutex is passed in the initializer, it will automatically be destroyed at the apropriate time (pass and forget). a mutex is not required if the fifo is used in a single-threaded context.
/// @param mutex optional mutex to be used for synchronization of the fifo chain. NULL if no internal synchronization is desired for the instance.
/// @return a heap pointer to a newly initialized `_cswiftslash_fifo_linkpair_t`. NOTE: this pointer must be closed with _cswiftslash_fifo_close to free all associated memory.
_cswiftslash_fifo_linkpair_ptr_t _cswiftslash_fifo_init(
	pthread_mutex_t *_Nullable mutex
);

/// @brief sets the maximum number of elements that can be buffered by the fifo if there is not a consumer immediately available.
/// @param chain pointer to the fifo to be capped.
/// @param max_elements maximum number of elements that can be stored in the chain.
/// @return `true` if the max elements was successfully set; `false` if the max elements could not be set.
bool _cswiftslash_fifo_set_max_elements(
	const _cswiftslash_fifo_linkpair_ptr_t chain,
	const size_t max_elements
);

/// @brief deinitializes a fifo instance, freeing all associated memory and resources.
/// @param chain pointer to the fifo to be deinitialized.
/// @param deallocator_f function used for deallocating the unconsumed elements in the chain. NULL if no deallocator is needed.
/// @return the cap pointer if the chain was capped (the capped pointer may be NULL); else, NULL is returned due to the chain not having a capped value. the caller is responsible for freeing this returned pointer from memory.
_cswiftslash_optr_t _cswiftslash_fifo_close(
	const _cswiftslash_fifo_linkpair_ptr_t chain,
	const _cswiftslash_fifo_link_ptr_consume_f _Nullable deallocator_f
);

// data handling

/// @brief cap off the fifo with a final element. any elements passed into the chain after capping it off will be stored and handled by the deallocator when this instance is closed (they will not be passed to a consumer).
/// @param chain pointer to the fifo to be capped.
/// @param ptr pointer to the final element to be added to the chain.
/// @return true if the cap pointer was successfully added; false if the cap could not be added.
bool _cswiftslash_fifo_pass_cap(
	const _cswiftslash_fifo_linkpair_ptr_t chain,
	const _cswiftslash_optr_t ptr
);

/// @brief inserts a new data pointer into the chain for storage and future processing. if the chain is capped, the data will be stored and handled by the deallocator when this instance is closed (it will not be passed to a consumer).
/// @param chain pointer to the fifo where data will be inserted.
/// @param ptr data pointer to be stored in the chain.
/// @return 0 on success. 1 when a retry should be done on the function call. -1 when the fifo is capped and no retry is necessary. -2 will be returned if the maximum number of elements has been reached.
int8_t _cswiftslash_fifo_pass(
	const _cswiftslash_fifo_linkpair_ptr_t chain,
	const _cswiftslash_ptr_t ptr
);

/// @brief consumes the next data pointer in the chain, removing it from the chain and returning it to the caller. NOTE: if the chain is empty, the function will return immediately with the apropriate return status indicating that the chain is empty.
/// @param chain pointer to the fifo where data will be consumed.
/// @param consumed_ptr pointer to the consumed data pointer.
/// @return the result of the consumption operation.
_cswiftslash_fifo_consume_result_t _cswiftslash_fifo_consume_nonblocking(
	const _cswiftslash_fifo_linkpair_ptr_t chain,
	_cswiftslash_optr_t *_Nonnull consumed_ptr
);

/// @brief consumes the next data pointer in the chain, removing it from the chain and returning it to the caller. NOTE: if the chain is empty, the function will block until a new element is added to the chain.
/// @param chain pointer to the fifo where data will be consumed.
/// @param consumed_ptr pointer to the consumed data pointer.
/// @return the result of the consumption operation.
_cswiftslash_fifo_consume_result_t _cswiftslash_fifo_consume_blocking(
	const _cswiftslash_fifo_linkpair_ptr_t chain,
	_cswiftslash_optr_t *_Nonnull consumed_ptr
);

#endif // _CSWIFTSLASH_FIFO_H