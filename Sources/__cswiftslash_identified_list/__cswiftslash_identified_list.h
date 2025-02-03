/*
LICENSE MIT
copyright (c) tanner silva 2024. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

#ifndef __CSWIFTSLASH_IDENTIFIED_LIST_H
#define __CSWIFTSLASH_IDENTIFIED_LIST_H

#include "__cswiftslash_types.h"

#include <pthread.h>
#include <stdint.h>
#include <stdbool.h>

/// forward declaration of the identified list structure.
struct __cswiftslash_identified_list;

/// nullable pointer to a single element in the atomic list.
typedef struct __cswiftslash_identified_list *_Nullable __cswiftslash_identified_list_ptr_t;

/// structure representing a single element within the atomic list.
typedef struct __cswiftslash_identified_list {
	/// unique key value associated with the data pointer.
	const uint64_t ____k;
	/// data pointer that the element instance is storing.
	const __cswiftslash_ptr_t ____d;
	/// next element that was stored in the hash table.
	struct __cswiftslash_identified_list *_Nullable ____n;
	/// previous element that was stored in the hash table.
	struct __cswiftslash_identified_list *_Nullable ____p;
} __cswiftslash_identified_list_t;

/// primary storage container for the atomic list.
typedef struct __cswiftslash_identified_list_pair {
	/// hash table array of pointers to linked lists.
	__cswiftslash_identified_list_ptr_t *_Nonnull ____ht;
	/// current size of the hash table.
	size_t ____hn;
	/// number of elements currently stored.
	size_t ____i;
	/// internal value that increments with each new item added.
	uint64_t ____idi;
	/// the previous element that was stored in the hash table.
	__cswiftslash_identified_list_ptr_t ____p;
	/// stores the oldest element in the hash table.
	__cswiftslash_identified_list_ptr_t ____o;
	/// mutex to keep the atomic list in a consistent state.
	pthread_mutex_t ____m;
} __cswiftslash_identified_list_pair_t;

/// non-null pointer to an atomic list pair.
typedef __cswiftslash_identified_list_pair_t *_Nonnull __cswiftslash_identified_list_pair_ptr_t;

// initialization and deinitialization functions.

/// initializes a new atomic list pair instance.
/// @return a new atomic list pair instance. Must be deallocated with `__cswiftslash_identified_list_close`.
__cswiftslash_identified_list_pair_t __cswiftslash_identified_list_init();

// data handling functions.

/// inserts a new data pointer into the atomic list.
/// @param _ pointer to the atomic list pair instance.
/// @param __ pointer to the data to be stored in the atomic list.
/// @return the new key value associated with the data pointer. this key will NEVER be zero.
uint64_t __cswiftslash_identified_list_insert(
	const __cswiftslash_identified_list_pair_ptr_t _,
	const __cswiftslash_ptr_t __
);

/// removes a key (and its corresponding stored pointer) from the atomic list.
/// @param _ pointer to the atomic list pair instance.
/// @param __ the key value of the element to be removed.
/// @return the data pointer that was removed from the atomic list. NULL if the key was not found.
__cswiftslash_optr_t __cswiftslash_identified_list_remove(
	const __cswiftslash_identified_list_pair_ptr_t _,
	const uint64_t __
);

/// @brief initiates a new iteration sequence over the identified list.
/// @param _ the instance to invoke the iteration sequence on.
/// @return a pointer (possibly NULL) to pass to one of numerous iteration functions. you must call your iteration function of choice ONCE with a null pointer to successfully terminate the iteration session.
__cswiftslash_identified_list_t *_Nullable __cswiftslash_identified_list_iterate_begin3(
	const __cswiftslash_identified_list_pair_ptr_t _
);

__cswiftslash_identified_list_t *_Nullable __cswiftslash_identified_list_iterate_step3(
	const __cswiftslash_identified_list_pair_ptr_t _,
	__cswiftslash_identified_list_t *_Nullable __,
	uint64_t *_Nonnull ___,
	__cswiftslash_ptr_t *_Nonnull ____
);

__cswiftslash_identified_list_t *_Nullable __cswiftslash_identified_list_iterate_step_zero3(
	const __cswiftslash_identified_list_pair_ptr_t _,
	__cswiftslash_identified_list_t *_Nullable __,
	uint64_t *_Nonnull ___,
	__cswiftslash_ptr_t *_Nonnull ____
);

__cswiftslash_identified_list_t *_Nullable __cswiftslash_identified_list_iterate_step_zero_close3(
	const __cswiftslash_identified_list_pair_ptr_t _,
	__cswiftslash_identified_list_t *_Nullable __,
	uint64_t *_Nonnull ___,
	__cswiftslash_ptr_t *_Nonnull ____
);

#endif // __CSWIFTSLASH_IDENTIFIED_LIST_H