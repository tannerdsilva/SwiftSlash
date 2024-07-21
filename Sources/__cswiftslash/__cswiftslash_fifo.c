// LICENSE MIT
// copyright (c) tanner silva 2024. all rights reserved.
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

/// internal function that initializes a chain pair.
/// - parameters:
///		- deallocator_f: the function that will be used to free the memory of the pointers in the chain.
_cswiftslash_fifo_linkpair_t _cswiftslash_fifo_init(pthread_mutex_t *_Nullable mutex) {
	
	if (mutex != NULL) {
		_cswiftslash_fifo_linkpair_t chain = {
			.base = NULL,
			.tail = NULL,
			.element_count = 0,
			._is_capped = false,
			.has_mutex = true,
			.mutex_optional = *mutex,
			.is_waiters_mutex_locked = false
		};
		pthread_mutex_init(&chain.waiters_mutex, NULL);
		return chain;
	} else {
		_cswiftslash_fifo_linkpair_t chain = {
			.base = NULL,
			.tail = NULL,
			.element_count = 0,
			._is_capped = false,
			.has_mutex = false,
			.is_waiters_mutex_locked = false
		};
		pthread_mutex_init(&chain.waiters_mutex, NULL);
		return chain;
	}
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
	
	if (chain->has_mutex) {
		pthread_mutex_destroy(&chain->mutex_optional);
	}

	if (atomic_load_explicit(&chain->is_waiters_mutex_locked, memory_order_acquire) == true) {
		pthread_mutex_unlock(&chain->waiters_mutex);
	}
	pthread_mutex_destroy(&chain->waiters_mutex);

	if (atomic_load_explicit(&chain->_is_capped, memory_order_acquire) == true) {
		return atomic_load_explicit(&chain->_cap_ptr, memory_order_acquire);
	} else {
		return NULL;
	}
}

bool _cswiftslash_fifo_pass_cap(const _cswiftslash_fifo_linkpair_ptr_t chain, const _cswiftslash_optr_t ptr) {
	// claim the internal sync mutex
	if (chain->has_mutex) {
		pthread_mutex_lock(&chain->mutex_optional);
	}

	bool expected_cap = false;	// we expect the chain to NOT be capped
	if (atomic_compare_exchange_weak_explicit(&chain->_is_capped, &expected_cap, true, memory_order_acq_rel, memory_order_relaxed)) {
		// successfully capped. now assign the capper pointer and store the number of remaining elements in the fifo.
		atomic_store_explicit(&chain->_cap_ptr, ptr, memory_order_release);

		// if there are waiters, unlock the waiters mutex.
		if (atomic_load_explicit(&chain->is_waiters_mutex_locked, memory_order_acquire) == true) {
			pthread_mutex_unlock(&chain->waiters_mutex);
			atomic_store_explicit(&chain->is_waiters_mutex_locked, false, memory_order_release);
		}

		// unlock the internal sync mutex
		if (chain->has_mutex) {
			pthread_mutex_unlock(&chain->mutex_optional);
		}
		return true;
	} else {
		// nothing to do, free the sync lock if it exists and then return
		if (chain->has_mutex) {
			pthread_mutex_unlock(&chain->mutex_optional);
		}
		return false;
	}
}

// internal function that attempts to install a link in the chain. this function does not care about the cap state of the chain and does not increment the element count.
// - returns: true if the install was successful. false if the install was not successful.
bool _cswiftslash_fifo_pass_link(const _cswiftslash_fifo_linkpair_ptr_t chain, const _cswiftslash_fifo_link_ptr_t link) {
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

/// user function that allows a user to pass a pointer to into the chain for processing.
/// - parameters:
///		- chain: the chain that this operation will act on.
///		- ptr: the pointer that will be passed into the chain for storage.
int8_t _cswiftslash_fifo_pass(const _cswiftslash_fifo_linkpair_ptr_t chain, const _cswiftslash_ptr_t ptr) {
	int8_t returnval = -1;
	if (chain->has_mutex) {
		pthread_mutex_lock(&chain->mutex_optional);
	}

	if (atomic_load_explicit(&chain->_is_capped, memory_order_acquire) == false) {
		const struct _cswiftslash_fifo_link link_on_stack = {
			.ptr = ptr,
			.next = NULL
		};
		const _cswiftslash_fifo_link_ptr_t link_on_heap = memcpy(malloc(sizeof(link_on_stack)), &link_on_stack, sizeof(link_on_stack));
		if (_cswiftslash_fifo_pass_link(chain, link_on_heap) == false) {
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
bool _cswiftslash_fifo_consume_next(_cswiftslash_fifo_link_ptr_t preloaded_atomic_base, const _cswiftslash_fifo_linkpair_ptr_t chain, _cswiftslash_ptr_t *_Nonnull consumed_ptr) {
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

/// @return 0 if the operation was successful and a normal fifo element was consumed. 1 if the operation resulted in the cap element being returned. -1 if the operation would block. -2 if the operation occurred an internal error.
_cswiftslash_fifo_consume_result_t _cswiftslash_fifo_consume_nonblocking(const _cswiftslash_fifo_linkpair_ptr_t chain, _cswiftslash_optr_t*_Nonnull consumed_ptr) {
	// get exclusivity of the state.
	if (chain->has_mutex) {
		pthread_mutex_lock(&chain->mutex_optional);
	}

	_cswiftslash_fifo_consume_result_t returnval;
	
	if (atomic_load_explicit(&chain->element_count, memory_order_acquire) > 0) {
		// attempt to consume the next entry in the chain.
		if (_cswiftslash_fifo_consume_next(atomic_load_explicit(&chain->base, memory_order_acquire), chain, consumed_ptr)) {
			returnval = FIFO_CONSUME_RESULT;
			goto returnTime;
		} else {
			returnval = FIFO_CONSUME_INTERNAL_ERROR;
			goto returnTime;
		}
	} else {
		// check if the chain is capped.
		if (__builtin_expect(atomic_load_explicit(&chain->_is_capped, memory_order_acquire) == false, true)){
			// no items and chain is NOT capped.
			returnval = FIFO_CONSUME_WOULDBLOCK;
			goto returnTime;
		} else {
			// the chain is capped. return the cap pointer.
			*consumed_ptr = atomic_load_explicit(&chain->_cap_ptr, memory_order_acquire);
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
		if (_cswiftslash_fifo_consume_next(atomic_load_explicit(&chain->base, memory_order_acquire), chain, consumed_ptr)) {
			returnval = FIFO_CONSUME_RESULT;
			goto returnTime;
		} else {
			returnval = FIFO_CONSUME_INTERNAL_ERROR;
			goto returnTime;
		}
	} else {
		// check if the chain is capped.
		if (__builtin_expect(atomic_load_explicit(&chain->_is_capped, memory_order_acquire) == false, true)) {
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
			*consumed_ptr = atomic_load_explicit(&chain->_cap_ptr, memory_order_acquire);
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