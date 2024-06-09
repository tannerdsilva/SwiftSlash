// LICENSE MIT
// copyright (c) tanner silva 2024. all rights reserved.
#include "_cswiftslash_identified_list.h"
#include "_cswiftslash_types.h"
#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <sys/types.h>

_cswiftslash_identified_list_pair_t _cswiftslash_identified_list_init_keyed() {
	_cswiftslash_identified_list_pair_t newVar = {
		.base = NULL,
		.element_count = 0,
		._id_increment_internal = 0,
	};
	pthread_mutex_init(&newVar.mutex, NULL);
	return newVar;
}

void _cswiftslash_identified_list_close_keyed(const _cswiftslash_identified_list_pair_ptr_t list, const _cswiftslash_identified_list_ptr_f consumer_f) {
	// iterate through the list and free all entries
	_cswiftslash_identified_list_ptr_t current = atomic_load_explicit(&list->base, memory_order_acquire);
	while (current != NULL) {
		_cswiftslash_identified_list_ptr_t next = atomic_load_explicit(&current->next, memory_order_acquire);
		consumer_f(current->key, current->ptr);
		free(current);
		current = next;
	}
	pthread_mutex_destroy(&list->mutex);
}

/// internal function. returns the next key that should be used for a new element in the atomic list. assumes that the returned key will be used, as such, this function steps the internal key counter for the next call.
/// @param list pointer to the atomic list pair instance.
/// @param value_out pointer to a uint64_t that will be written to with the next key value.
/// @return true if the key was successfully written to the pointer, false if the key could not be written.
bool _cswiftslash_al_next_key(const _cswiftslash_identified_list_pair_ptr_t list, uint64_t *value_out) {
	// load the existing value.
	uint64_t acquireValue = atomic_load_explicit(&list->_id_increment_internal, memory_order_acquire);
	
	// check if the integer is about to overflow (irrationally padded by 64 because safety is my style)
	if (__builtin_expect(acquireValue < (ULLONG_MAX - 64), true)) {
		// no overflow anticipated. increment the existing value and attempt to write it to the atomic location where this value is stored.
		if (__builtin_expect(atomic_compare_exchange_weak_explicit(&list->_id_increment_internal, &acquireValue, acquireValue + 1, memory_order_release, memory_order_acquire), true)) {
			// successful case. write the new value to the passed uint64_t pointer
			(*value_out) = acquireValue;
			return true; // successful write.
		} else {
			// unsuccessful case. write couldn't be successfully completed.
			return false; // unsuccessful write.
		}
	} else {
		// overflow anticipated. zero value or bust.
		if (__builtin_expect(atomic_compare_exchange_strong_explicit(&list->_id_increment_internal, &acquireValue, 0, memory_order_release, memory_order_acquire), true)) {
			(*value_out) = acquireValue;
			return true; // successful write.
		} else {
			return false; // unsuccessful write.
		}
	}
}

/// internal function that installs a packaged data element into the atomic list.
/// @param list pointer to the atomic list pair instance.
/// @param item pointer to the atomic list element to be installed.
/// @return true if the element was successfully installed, false if the element could not be installed.
bool _cswiftslash_al_insert_internal(const _cswiftslash_identified_list_pair_ptr_t list, const _cswiftslash_identified_list_ptr_t item) {
	// load the current base
    _cswiftslash_identified_list_ptr_t expectedbase = atomic_load_explicit(&list->base, memory_order_acquire);
	
	// write the new item to the list
	if (__builtin_expect(atomic_compare_exchange_strong_explicit(&list->base, &expectedbase, item, memory_order_release, memory_order_acquire), true)) {
		// make sure that the next item in this base correctly references the old base value
		atomic_store_explicit(&item->next, expectedbase, memory_order_release);
		// increment the element count
		atomic_fetch_add_explicit(&list->element_count, 1, memory_order_acq_rel);
		return true; // successful write.
	} else {
		return false; // unsuccessful write.
	}
}

/// inserts a new data pointer into the atomic list for storage and future processing.
/// @param list pointer to the atomic list pair instance.
/// @param ptr pointer to the data to be stored in the atomic list.
/// @return true if the element was successfully inserted, false if the element could not be inserted.
uint64_t _cswiftslash_identified_list_insert(const _cswiftslash_identified_list_pair_ptr_t list, const _cswiftslash_ptr_t ptr) {
	uint64_t new_id_internal;
	pthread_mutex_lock(&list->mutex);
	// acquire an unused key for the new element. if this fails (not expected), retry until it succeeds.
	while (__builtin_expect(_cswiftslash_al_next_key(list, &new_id_internal) == false, false)) {}
	// package the new item on stack memory, with the new key and the pointer to the data.
    const _cswiftslash_identified_list_t link_on_stack = {
        .key = new_id_internal,
        .ptr = ptr,
        .next = NULL
    };
	// while (true) {}
	// copy the stack memory to heap memory, and insert the heap memory into the atomic list.
    const _cswiftslash_identified_list_ptr_t link_on_heap = memcpy(malloc(sizeof(link_on_stack)), &link_on_stack, sizeof(link_on_stack));
   	while (__builtin_expect(_cswiftslash_al_insert_internal(list, link_on_heap) == false, false)) {}
	pthread_mutex_unlock(&list->mutex);
	return new_id_internal;
}

/// internal function that removes an element from the atomic list.
/// @return zero under normal conditions. 1 if the element was removed and the ptr_out was set to the removed pointer. -1 if the function should be called again.
int8_t _cswiftslash_al_remove_try(_cswiftslash_identified_list_aptr_t*_Nonnull base, const uint64_t key, _cswiftslash_ptr_t*_Nonnull ptr_out) {
	_cswiftslash_identified_list_ptr_t current = atomic_load_explicit(base, memory_order_acquire);
	while (current != NULL) {
		
		// load the next item of current
		_cswiftslash_identified_list_ptr_t next = atomic_load_explicit(&current->next, memory_order_acquire);
		
		// compare the key of current
		if (current->key == key) {

			// remove the current item from the list. if it fails, the whole operation should be retried.
			if (__builtin_expect(atomic_compare_exchange_strong_explicit(base, &current, next, memory_order_release, memory_order_relaxed) == false, false)) {
				return -1; // retry
			}
			
			// remove successful. fire the consumer and handle the removal here
			*ptr_out = current->ptr;
			free(current);
			return 1; // successful removal
		}

		// increment for next iteration
		base = &current->next;
		current = next;
	}
	// no element was found with the key.
	return 0;
}

_cswiftslash_optr_t _cswiftslash_identified_list_remove(const _cswiftslash_identified_list_pair_ptr_t list, const uint64_t key) {
	_cswiftslash_ptr_t retval;
	int8_t result;
	pthread_mutex_lock(&list->mutex);
	do {
		result = _cswiftslash_al_remove_try(&list->base, key, &retval);
	} while (__builtin_expect(result == -1, false));
	if (result == 1) {
		atomic_fetch_sub_explicit(&list->element_count, 1, memory_order_acq_rel);
		pthread_mutex_unlock(&list->mutex);
		return (_cswiftslash_optr_t)retval;
	} else {
		pthread_mutex_unlock(&list->mutex);
		return (_cswiftslash_optr_t)NULL;
	}
}

void _cswiftslash_identified_list_iterate(const _cswiftslash_identified_list_pair_ptr_t list, const _cswiftslash_identified_list_ptr_f consumer_f) {
	// the list is not being modified. iterate through the list.
	pthread_mutex_lock(&list->mutex);
	_cswiftslash_identified_list_ptr_t current = atomic_load_explicit(&list->base, memory_order_acquire);
	while (current != NULL) {
		consumer_f(current->key, current->ptr);
		current = atomic_load_explicit(&current->next, memory_order_acquire);
	}
	pthread_mutex_unlock(&list->mutex);
}