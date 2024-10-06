/* LICENSE MIT
copyright (c) tanner silva 2024. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

#include "__cswiftslash_fifo.h"

#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

pthread_mutex_t _cswiftslash_fifo_mutex_new() {
	pthread_mutex_t mutex;
	pthread_mutex_init(&mutex, NULL);
	return mutex;
}

_cswiftslash_fifo_linkpair_ptr_t _cswiftslash_fifo_init(pthread_mutex_t *_Nullable mutex) {
	if (mutex != NULL) {

		// initialize WITH a mutex
		_cswiftslash_fifo_linkpair_t chain = {
			.base = NULL,
			.tail = NULL,
			.element_count = 0,
			.is_capped = false,
			.has_mutex = true,
			.mutex_optional = *mutex,
			.is_waiters_mutex_locked = false,
			.has_max_elements = false,
			.max_elements = 0
		};
		pthread_mutex_init(&chain.waiters_mutex, NULL);

		void *rptr = malloc(sizeof(_cswiftslash_fifo_linkpair_t));
		memcpy(rptr, &chain, sizeof(_cswiftslash_fifo_linkpair_t));\

		return rptr;

	} else {

		// initialize WITHOUT a mutex
		_cswiftslash_fifo_linkpair_t chain = {
			.base = NULL,
			.tail = NULL,
			.element_count = 0,
			.is_capped = false,
			.has_mutex = false,
			.is_waiters_mutex_locked = false,
			.has_max_elements = false,
			.max_elements = 0
		};
		pthread_mutex_init(&chain.waiters_mutex, NULL);

		void *rptr = malloc(sizeof(_cswiftslash_fifo_linkpair_t));
		memcpy(rptr, &chain, sizeof(_cswiftslash_fifo_linkpair_t));

		return rptr;

	}
}

bool _cswiftslash_fifo_set_max_elements(const _cswiftslash_fifo_linkpair_ptr_t chain, const size_t max_elements) {
	// this is the value that the function will return.
	bool returnValue = false;

	// acquire the resource lock to synchronize the state of the chain.
	if (chain->has_mutex) {
		pthread_mutex_lock(&chain->mutex_optional);
	}

	// validate that the chain is not already capped.
	if (atomic_load_explicit(&chain->is_capped, memory_order_acquire) == true) {
		goto returnTime;
	}

	// do not cap the chain if there are already more elements than the new cap.
	if (atomic_load_explicit(&chain->element_count, memory_order_acquire) > max_elements) {
		goto returnTime;
	}

	// set the cap and store the max elements.
	atomic_store_explicit(&chain->has_max_elements, true, memory_order_release);
	atomic_store_explicit(&chain->max_elements, max_elements, memory_order_release);
	returnValue = true;

	// cleans up the function and returns the result value to the caller.
	returnTime:
		if (chain->has_mutex) {
			pthread_mutex_unlock(&chain->mutex_optional);
		}
		return returnValue;
}

_cswiftslash_optr_t _cswiftslash_fifo_close(const _cswiftslash_fifo_linkpair_ptr_t chain, const _cswiftslash_fifo_link_ptr_consume_f _Nullable deallocator_f) {
	// load the base entry.
	_cswiftslash_fifo_link_ptr_t current = atomic_load_explicit(&chain->base, memory_order_acquire);
	
	// place NULL at the base and tail so that others aren't able to manipulate the chain while we work to free it.
	atomic_store_explicit(&chain->base, NULL, memory_order_release);
	atomic_store_explicit(&chain->tail, NULL, memory_order_release);
	
	// iterate through the chain and free all entries. call the deallocator function if it is not NULL.
	if (deallocator_f != NULL) {
		while (current != NULL) {
			_cswiftslash_fifo_link_ptr_t next = atomic_load_explicit(&current->next, memory_order_acquire);
			deallocator_f(current->ptr);
			free(current);
			current = next;
		}
	} else {
		while (current != NULL) {
			_cswiftslash_fifo_link_ptr_t next = atomic_load_explicit(&current->next, memory_order_acquire);
			free(current);
			current = next;
		}
	}
	
	// destroy the mutexes if they exist.
	if (chain->has_mutex) {
		pthread_mutex_destroy(&chain->mutex_optional);
	}

	// unlock the waiters mutex if it is locked.
	if (atomic_load_explicit(&chain->is_waiters_mutex_locked, memory_order_acquire) == true) {
		pthread_mutex_unlock(&chain->waiters_mutex);
	}

	// destroy the waiters mutex.
	pthread_mutex_destroy(&chain->waiters_mutex);

	// this will store the return value of the function.
	_cswiftslash_optr_t rptr = NULL;

	// return the cap pointer if the chain is capped.
	if (atomic_load_explicit(&chain->is_capped, memory_order_acquire) == true) {
		rptr = atomic_load_explicit(&chain->cap_ptr, memory_order_acquire);
	} else {
		rptr = NULL;
	}

	// free the chain structure.
	free(chain);

	return rptr;
}

bool _cswiftslash_fifo_pass_cap(const _cswiftslash_fifo_linkpair_ptr_t chain, const _cswiftslash_optr_t ptr) {
	// this is the value that the function will return.
	bool returnValue = false;

	// claim the internal sync mutex
	if (chain->has_mutex) {
		pthread_mutex_lock(&chain->mutex_optional);
	}

	bool expected_cap = false;	// we expect the chain to NOT be capped

	if (atomic_compare_exchange_weak_explicit(&chain->is_capped, &expected_cap, true, memory_order_acq_rel, memory_order_relaxed)) {
		// successfully capped. now assign the capper pointer and store the number of remaining elements in the fifo.
		atomic_store_explicit(&chain->cap_ptr, ptr, memory_order_release);

		// if there are waiters, unlock the waiters mutex.
		if (atomic_load_explicit(&chain->is_waiters_mutex_locked, memory_order_acquire) == true) {
			pthread_mutex_unlock(&chain->waiters_mutex);
			atomic_store_explicit(&chain->is_waiters_mutex_locked, false, memory_order_release);
		}

		// unlock the internal sync mutex
		returnValue = true;
		goto returnTime;

	} else {

		// nothing to do, free the sync lock if it exists and then return
		returnValue = false;
		goto returnTime;
	}

	returnTime:
		if (chain->has_mutex) {
			pthread_mutex_unlock(&chain->mutex_optional);
		}
		return returnValue;
}

bool ____cswiftslash_fifo_pass_link(const _cswiftslash_fifo_linkpair_ptr_t chain, const _cswiftslash_fifo_link_ptr_t link) {
	// defines the value that we expect to find on the element we will append to. we must only append to the end of the chain, so we expect the next pointer to be NULL.
	_cswiftslash_fifo_link_ptr_t expected = NULL;
	
	// load the current tail entry. it may exist, or it may not.
	_cswiftslash_fifo_link_ptr_t gettail = atomic_load_explicit(&chain->tail, memory_order_acquire);

	// determine where to try and write the new entry based on whether or not there is a tail entry.
	_cswiftslash_fifo_link_aptr_t*_Nonnull writeptr;
	_cswiftslash_fifo_link_aptr_t*_Nonnull secondptr;
	if (gettail == NULL) {
		writeptr = &chain->tail;
		secondptr = &chain->base;
	} else {
		writeptr = &gettail->next;
		secondptr = &chain->tail;
	}

	// attempt to write the new entry to the chain.
	if (atomic_compare_exchange_weak_explicit(writeptr, &expected, link, memory_order_acq_rel, memory_order_relaxed)) {
		// swap successful, now write the secondary pointer if necessary.
		atomic_store_explicit(secondptr, link, memory_order_release);
		return true;
	} else {
		return false;
	}
}

int8_t _cswiftslash_fifo_pass(const _cswiftslash_fifo_linkpair_ptr_t chain, const _cswiftslash_ptr_t ptr) {
	int8_t returnval = -1;
	if (chain->has_mutex) {
		pthread_mutex_lock(&chain->mutex_optional);
	}

	// check if the chain is capped.
	if (atomic_load_explicit(&chain->is_capped, memory_order_acquire) == false) {
		// not capped. continue validation before adding.

		// verify that the maximum number of elements has not been reached.
		if (atomic_load_explicit(&chain->has_max_elements, memory_order_acquire) == true) {
			// max elements is set. check if the chain is full.
			if (atomic_load_explicit(&chain->element_count, memory_order_acquire) >= atomic_load_explicit(&chain->max_elements, memory_order_acquire)) {
				returnval = -2;
				goto returnTime;
			}
		}
		
		// create a new link to be added to the chain. this will be defined on the stack.
		const struct _cswiftslash_fifo_link link_on_stack = {
			.ptr = ptr,
			.next = NULL
		};

		// copy the new link to the heap.
		const _cswiftslash_fifo_link_ptr_t link_on_heap = memcpy(malloc(sizeof(link_on_stack)), &link_on_stack, sizeof(link_on_stack));

		// attempt to pass the link into the chain.
		if (____cswiftslash_fifo_pass_link(chain, link_on_heap) == false) {
			// failure condition.
			free(link_on_heap);
			returnval = 1; // retry
			goto returnTime;
		}

		// the chain is not capped so we must increment the element count.
		atomic_fetch_add_explicit(&chain->element_count, 1, memory_order_acq_rel);

		// signal any waiting threads that there is a new element in the chain.
		if (atomic_load_explicit(&chain->is_waiters_mutex_locked, memory_order_acquire) == true) {
			pthread_mutex_unlock(&chain->waiters_mutex);
			atomic_store_explicit(&chain->is_waiters_mutex_locked, false, memory_order_release);
		}

		// success condition.
		returnval = 0;
		goto returnTime;
		
	} else {

		// the chain is capped. we cannot add any more elements.
		returnval = -1;
		goto returnTime;
	}

	returnTime:
		if (chain->has_mutex) {
			pthread_mutex_unlock(&chain->mutex_optional);
		}
		return returnval;
}

/// internal function that flushes a single writerchain entry.
/// - parameters:
///		- preloaded_atomic_base: the pre-loaded atomic base pointer of the chain.
///		- chain: the chain that this operation will act on.
///		- consumed_ptr: the pointer that will be set to the consumed pointer.
/// - returns: true if the operation was successful and the element count could be decremented. false if the operation was not successful.
bool ____cswiftslash_fifo_consume_next(_cswiftslash_fifo_link_ptr_t preloaded_atomic_base, const _cswiftslash_fifo_linkpair_ptr_t chain, _cswiftslash_ptr_t *_Nonnull consumed_ptr) {
	if (preloaded_atomic_base == NULL) {
		// there are no entries to consume.
		return false;
	}

	// load the next entry from the base.
	_cswiftslash_fifo_link_ptr_t next = atomic_load_explicit(&preloaded_atomic_base->next, memory_order_acquire);

	// attempt to pop the next entry from the chain by replacing the current base with the next entry.
	if (atomic_compare_exchange_weak_explicit(&chain->base, &preloaded_atomic_base, next, memory_order_acq_rel, memory_order_relaxed)) {
		// successfully popped
		if (next == NULL) {
			// there are no more entries in the chain. write the tail to NULL to reflect this.
			atomic_store_explicit(&chain->tail, NULL, memory_order_release);
		}
		// decrement the atomic count to reflect the entry being consumed.
		atomic_fetch_sub_explicit(&chain->element_count, 1, memory_order_acq_rel);
		*consumed_ptr = preloaded_atomic_base->ptr;
		free((void*)preloaded_atomic_base);
		return true;
	}
	return false;
}

_cswiftslash_fifo_consume_result_t _cswiftslash_fifo_consume_nonblocking(const _cswiftslash_fifo_linkpair_ptr_t chain, _cswiftslash_optr_t *_Nonnull consumed_ptr) {
	// get exclusivity of the state.
	if (chain->has_mutex) {
		pthread_mutex_lock(&chain->mutex_optional);
	}

	_cswiftslash_fifo_consume_result_t returnval;
	
	if (atomic_load_explicit(&chain->element_count, memory_order_acquire) > 0) {

		// attempt to consume the next entry in the chain.
		if (____cswiftslash_fifo_consume_next(atomic_load_explicit(&chain->base, memory_order_acquire), chain, consumed_ptr)) {
			returnval = FIFO_CONSUME_RESULT;
			goto returnTime;
		} else {
			returnval = FIFO_CONSUME_INTERNAL_ERROR;
			goto returnTime;
		}

	} else {

		// check if the chain is capped.
		if (__builtin_expect(atomic_load_explicit(&chain->is_capped, memory_order_acquire) == false, true)){
			// no items and chain is NOT capped.
			returnval = FIFO_CONSUME_WOULDBLOCK;
			goto returnTime;
		} else {
			// the chain is capped. return the cap pointer.
			*consumed_ptr = atomic_load_explicit(&chain->cap_ptr, memory_order_acquire);
			returnval = FIFO_CONSUME_CAP;
			goto returnTime;
		}

	}

	returnTime:
		// no longer need exclusivity of the state.
		if (chain->has_mutex) {
			pthread_mutex_unlock(&chain->mutex_optional);
		}
		return returnval;
}

_cswiftslash_fifo_consume_result_t _cswiftslash_fifo_consume_blocking(const _cswiftslash_fifo_linkpair_ptr_t chain, _cswiftslash_optr_t*_Nonnull consumed_ptr) {
	bool wasLockClaimedByCallAlready = false;
	
	loadAgain:
		// get exclusivity of the state.
		if (chain->has_mutex) {
			pthread_mutex_lock(&chain->mutex_optional);
		}

		// if this function was called before, we need to unlock the waiters mutex.
		if (wasLockClaimedByCallAlready == true) {
			wasLockClaimedByCallAlready = false;
			atomic_store_explicit(&chain->is_waiters_mutex_locked, false, memory_order_release);
			pthread_mutex_unlock(&chain->waiters_mutex);
		}

		// this is the code that will be returned when the function is done.
		_cswiftslash_fifo_consume_result_t returnval;
		
		if (atomic_load_explicit(&chain->element_count, memory_order_acquire) > 0) {
			// attempt to consume the next entry in the chain.
			if (____cswiftslash_fifo_consume_next(atomic_load_explicit(&chain->base, memory_order_acquire), chain, consumed_ptr)) {
				returnval = FIFO_CONSUME_RESULT;
				goto returnTime;
			} else {
				returnval = FIFO_CONSUME_INTERNAL_ERROR;
				goto returnTime;
			}
		} else {
			// check if the chain is capped.
			if (__builtin_expect(atomic_load_explicit(&chain->is_capped, memory_order_acquire) == false, true)) {
				// not capped, so we must wait for an element to be added.
				bool expectedLock = false;
				if (atomic_compare_exchange_weak_explicit(&chain->is_waiters_mutex_locked, &expectedLock, true, memory_order_acq_rel, memory_order_relaxed)) {
					// acquire the waiters mutex. this should NOT block because there was no contention indicated in the atomic exchange.
					pthread_mutex_lock(&chain->waiters_mutex);
				} else {
					abort();
				}
				// we can now free the internal sync mutex.
				if (chain->has_mutex) {
					pthread_mutex_unlock(&chain->mutex_optional);
				}
				goto blockForNext;
			} else {
				// the chain is capped. return the cap pointer.
				*consumed_ptr = atomic_load_explicit(&chain->cap_ptr, memory_order_acquire);
				returnval = FIFO_CONSUME_CAP;
				goto returnTime;
			}
		}

	blockForNext:
		pthread_mutex_lock(&chain->waiters_mutex);
		wasLockClaimedByCallAlready = true;
		goto loadAgain;

	returnTime:

		// no longer need exclusivity of the state.
		if (chain->has_mutex) {
			pthread_mutex_unlock(&chain->mutex_optional);
		}
		return returnval;
}