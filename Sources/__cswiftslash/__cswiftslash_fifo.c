// LICENSE MIT
// copyright (c) tanner silva 2024. all rights reserved.
#include "__cswiftslash_fifo.h"
#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/// internal function that initializes a chain pair.
/// - parameters:
///		- deallocator_f: the function that will be used to free the memory of the pointers in the chain.
_cswiftslash_fifo_linkpair_t _cswiftslash_fifo_init() {
	_cswiftslash_fifo_linkpair_t chain = {
		.base = NULL,
		.tail = NULL,
		.element_count = 0,
		._is_capped = false,
	};
	pthread_mutex_init(&chain.mutex, NULL);
	return chain;
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
	
	pthread_mutex_destroy(&chain->mutex);

	if (atomic_load_explicit(&chain->_is_capped, memory_order_acquire) == true) {
		return atomic_load_explicit(&chain->_cap_ptr, memory_order_acquire);
	} else {
		return NULL;
	}
}

bool _cswiftslash_fifo_pass_cap(const _cswiftslash_fifo_linkpair_ptr_t chain, const _cswiftslash_optr_t ptr) {
	bool expected_cap = false;	// we expect the chain to NOT be capped
	if (atomic_compare_exchange_strong_explicit(&chain->_is_capped, &expected_cap, true, memory_order_release, memory_order_acquire)) {
		// successfully capped. now assign the capper pointer and store the number of remaining elements in the fifo.
		atomic_store_explicit(&chain->_cap_ptr, ptr, memory_order_release);
		return true;
	} else {
		return false;
	}
}

// internal function that attempts to install a link in the chain. this function does not care about the cap state of the chain and does not increment the element count.
// - returns: true if the install was successful. false if the install was not successful.
bool _cswiftslash_fifo_pass_link(const _cswiftslash_fifo_linkpair_ptr_t chain, const _cswiftslash_fifo_link_ptr_t link) {
	// defines the value that we expect to find on the element we will append to...
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
	if (atomic_compare_exchange_strong_explicit(writeptr, &expected, link, memory_order_release, memory_order_acquire)) {
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
	pthread_mutex_lock(&chain->mutex);

	if (atomic_load_explicit(&chain->_is_capped, memory_order_acquire) == false) {
		const struct _cswiftslash_fifo_link link_on_stack = {
			.ptr = ptr,
			.next = NULL
		};
		const _cswiftslash_fifo_link_ptr_t link_on_heap = memcpy(malloc(sizeof(link_on_stack)), &link_on_stack, sizeof(link_on_stack));
		if (_cswiftslash_fifo_pass_link(chain, link_on_heap) == false) {
			free(link_on_heap);
			pthread_mutex_unlock(&chain->mutex);
			return 1; // retry
		}

		// the chain is not capped so we must increment the element count.
		atomic_fetch_add_explicit(&chain->element_count, 1, memory_order_acq_rel);
		pthread_mutex_unlock(&chain->mutex);
		return 0; // success
	} else {
		// the chain is capped. we cannot add any more elements.
		pthread_mutex_unlock(&chain->mutex);
		return -1;
	}
}

/// internal function that flushes a single writerchain entry.
/// - parameters:
///		- preloaded_atomic_base: the pre-loaded atomic base pointer of the chain.
///		- chain: the chain that this operation will act on.
///		- consumed_ptr: the pointer that will be set to the consumed pointer.
/// - returns: true if the operation was successful and the element count could be decremented. false if the operation was not successful.
bool _cswiftslash_fifo_consume_next(_cswiftslash_fifo_link_ptr_t preloaded_atomic_base, const _cswiftslash_fifo_linkpair_ptr_t chain, _cswiftslash_ptr_t *_Nonnull consumed_ptr) {
// 	pthread_mutex_lock(&chain->mutex);
	if (preloaded_atomic_base == NULL) {
		// there are no entries to consume.
		return false;
	}

	// load the next entry from the base.
	_cswiftslash_fifo_link_ptr_t next = atomic_load_explicit(&preloaded_atomic_base->next, memory_order_acquire);

	// attempt to pop the next entry from the chain by replacing the current base with the next entry.
	if (atomic_compare_exchange_strong_explicit(&chain->base, &preloaded_atomic_base, next, memory_order_release, memory_order_relaxed)) {
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
int8_t _cswiftslash_fifo_consume_nonblocking(const _cswiftslash_fifo_linkpair_ptr_t chain, _cswiftslash_optr_t*_Nonnull consumed_ptr) {
	pthread_mutex_lock(&chain->mutex);
	if (atomic_load_explicit(&chain->element_count, memory_order_acquire) > 0) {
		// attempt to consume the next entry in the chain.
		if (_cswiftslash_fifo_consume_next(atomic_load_explicit(&chain->base, memory_order_acquire), chain, consumed_ptr)) {
			pthread_mutex_unlock(&chain->mutex);
			return 0; // normal fifo element
		} else {
			pthread_mutex_unlock(&chain->mutex);
			return -2; // internal error
		}
	} else {
		// check if the chain is capped.
		if (__builtin_expect(atomic_load_explicit(&chain->_is_capped, memory_order_acquire) == false, true)){
			// no items and chain is NOT capped.
			pthread_mutex_unlock(&chain->mutex);
			return -1; // would block
		} else {
			// the chain is capped. return the cap pointer.
			*consumed_ptr = atomic_load_explicit(&chain->_cap_ptr, memory_order_acquire);
			pthread_mutex_unlock(&chain->mutex);
			return 1; // cap element
		}
	}
}