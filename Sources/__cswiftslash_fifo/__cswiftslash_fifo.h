/*
LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

#ifndef __CSWIFTSLASH_FIFO_H
#define __CSWIFTSLASH_FIFO_H

#include "__cswiftslash_types.h"

#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>

/// forward declaration of the fifo link structure. represents a single link (a single element) in a chain of n number of elements. a foundational structure for the fifo mechanism.
struct __cswiftslash_fifo_link;

/// a nullable pointer to a fifo link structure, allowing for the construction of chains of link elements.
typedef struct __cswiftslash_fifo_link *_Nullable __cswiftslash_fifo_link_ptr_t;

/// defines an atomic version of `_cswiftslash_fifo_link_ptr_t` to ensure thread-safe manipulation of the fifo links.
typedef _Atomic __cswiftslash_fifo_link_ptr_t __cswiftslash_fifo_link_aptr_t;

/// function prototype for consuming data from the chain.
typedef void (* __cswiftslash_fifo_link_ptr_consume_f)(
	const __cswiftslash_ptr_t,
	const __cswiftslash_optr_t
);

/// fifo consumption result values
typedef enum __cswiftslash_fifo_consume_result {

	/// returned when a fifo element is consumed and returned to the caller normally.
	__CSWIFTSLASH_FIFO_CONSUME_RESULT = 0,
	/// returned when the fifo is "capped off" and as such, there are no more elements to consume. cap pointer is returned with this result.
	__CSWIFTSLASH_FIFO_CONSUME_CAP = 1,
	/// returned when the fifo element is empty and the consumer would block until a new element is added.
	__CSWIFTSLASH_FIFO_CONSUME_WOULDBLOCK = 2,
	/// returned when an internal error occurs during the consumption process.
	__CSWIFTSLASH_FIFO_CONSUME_INTERNAL_ERROR = 3,

} __cswiftslash_fifo_consume_result_t;

/// structure representing a single link within the fifo, stores a data item and a pointer to the next chain item.
typedef struct __cswiftslash_fifo_link {

	/// pointer to the link items stored data.
	const __cswiftslash_ptr_t _;
	/// pointer to the next link in the chain.
	__cswiftslash_fifo_link_aptr_t __;

} __cswiftslash_fifo_link_t;

/// structure representing a pair of pointers to the head and tail of a fifo, enabling efficient management and access to both ends of the chain. stores an assortment of other metadata to facilitate efficient and safe operation of the fifo mechanism. NOTE: none of the fields in this structure need to be accessed directly by the caller.
typedef struct __cswiftslash_fifo_linkpair {

	/// pointer to the base (head) of the chain, serving as the entry point to the first element.
	__cswiftslash_fifo_link_aptr_t ____bp;
	/// pointer to the tail of the chain, enabling efficient addition of new elements to the end of the chain.
	__cswiftslash_fifo_link_aptr_t ____tp;

	/// atomic counter representing the number of elements stored in the chain.
	_Atomic size_t ____ec;

	/// atomic boolean flag indicating whether the fifo is capped.
	_Atomic bool ____ic;
	
	/// atomic pointer to the cap pointer, which is the final element in the chain.
	_Atomic __cswiftslash_optr_t ____cp;
	
	// mutex used to synchronize the internal state of the fifo. this is optional because there may be parent structures that are synchronized in the same way, therefore, can opt out of the built in synchronization to eliminate overhead.
	/// atomic boolean flag indicating whether the chain is configured with an internal mutex.
	const bool ____hm;
	/// mutex used to synchronize the internal state of the fifo.
	pthread_mutex_t ____m;

	// mutex used to signal to waiting threads when a result is available again. one may argue that there are better pthread primitives to use for this, but the swift runtime only wants to operate with mutexes.
	/// atomic boolean flag indicating whether the chain is currently locked by a waiting thread.
	_Atomic bool ____iwlk;
	/// mutex used to signal to waiting threads when a result is available again.
	pthread_mutex_t ____wm;

	/// atomic boolean flag indicating whether the chain is currently configured with a maximum number of elements.
	_Atomic bool ____hme;
	/// atomic size_t representing the maximum number of elements that can be stored in the chain.
	_Atomic size_t ____me;

} __cswiftslash_fifo_linkpair_t;

/// defines a non-null pointer to a fifo pair structure, facilitating operations on the entire chain.
typedef __cswiftslash_fifo_linkpair_t*_Nonnull __cswiftslash_fifo_linkpair_ptr_t;

/// initializes a new fifo pair. can be initialized with or without an internal mutex for state synchronization.
/// @param _ boolean value indicating if the fifo should be initialized with its own internal mutex for synchronization. `FALSE` can be passed here when the fifo is used in a single-threaded context.
/// @return a heap pointer to a newly initialized `_cswiftslash_fifo_linkpair_t`. NOTE: this pointer must be closed with `__cswiftslash_fifo_close` to free all associated memory.
__cswiftslash_fifo_linkpair_ptr_t __cswiftslash_fifo_init(
	const bool _
);

/// sets the maximum number of elements that can be buffered by the fifo if there is not a consumer immediately available.
/// @param _ pointer to the fifo to assign the element limit to.
/// @param __ the maximum number of elements that can be stored in the chain.
/// @return `true` if the max elements was successfully set; `false` if the max elements could not be set.
bool __cswiftslash_fifo_set_max_elements(
	const __cswiftslash_fifo_linkpair_ptr_t _,
	const size_t __
);

/// deinitializes a fifo instance, freeing all associated memory and resources.
/// @param _ pointer to the fifo to be deinitialized.
/// @param __ function used for deallocating the unconsumed elements in the chain.
/// @param ___ the context pointer to be passed to the deallocator consume function.
/// @param ____ a pointer to the memory space where the capped pointer can be stored, if the chain was capped.
/// @return boolean value indicating if the fifo was capped.
bool __cswiftslash_fifo_close(
	const __cswiftslash_fifo_linkpair_ptr_t _,
	const __cswiftslash_fifo_link_ptr_consume_f _Nonnull __,
	const __cswiftslash_optr_t ___,
	__cswiftslash_optr_t *_Nonnull ____
);

/// cap off the fifo with a final element. any elements passed into the chain after capping it off will be stored and handled by the deallocator when this instance is closed (they will not be passed to a consumer, nor will they be forever leaked into memory).
/// @param _ pointer to the fifo to be capped.
/// @param __ pointer to the final element to be added to the chain.
/// @return `true` if the cap pointer was successfully added; `false` if the cap could not be added.
bool __cswiftslash_fifo_pass_cap(
	const __cswiftslash_fifo_linkpair_ptr_t _,
	const __cswiftslash_optr_t __
);

/// inserts a new data pointer into the chain for storage and future processing. if the chain is capped, the data will be stored and handled by the deallocator when this instance is closed (it will not be passed to a consumer).
/// @param _ pointer to the fifo that will store the new data.
/// @param __ data pointer to be stored in the chain.
/// @return `0` on success. `1` when a retry should be done on the function call. `-1` when the fifo is capped and no retry is necessary. `-2` will be returned if the maximum number of elements has been reached.
int8_t __cswiftslash_fifo_pass(
	const __cswiftslash_fifo_linkpair_ptr_t _,
	const __cswiftslash_ptr_t __
);

/// consumes the next data pointer in the chain, removing it from the chain and returning it to the caller.
/// @param _ pointer to the fifo to pop data from.
/// @param __ memory location to store the popped data pointer after if one was successfully consumed from the chain.
/// @return the result of the consumption operation.
__cswiftslash_fifo_consume_result_t __cswiftslash_fifo_consume_nonblocking(
	const __cswiftslash_fifo_linkpair_ptr_t _,
	__cswiftslash_optr_t *_Nonnull __
);

/// consumes the next data pointer in the chain, removing it from the chain and returning it to the caller. NOTE: if the chain is empty, the function will block until a new element is added to the chain.
/// @param _ pointer to the fifo where data will be consumed.
/// @param __ pointer to the consumed data pointer.
/// @return the result of the consumption operation.
__cswiftslash_fifo_consume_result_t __cswiftslash_fifo_consume_blocking(
	const __cswiftslash_fifo_linkpair_ptr_t _,
	__cswiftslash_optr_t *_Nonnull __
);

#endif // __CSWIFTSLASH_FIFO_H