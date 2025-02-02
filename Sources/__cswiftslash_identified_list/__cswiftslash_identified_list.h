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
/// defines an atomic pointer to a single element in the atomic list.
typedef __cswiftslash_identified_list_ptr_t __cswiftslash_identified_list_ptr_t;
/// consumer function prototype for processing data pointers in the atomic list. this is essentially the "last point of contact" for the data pointer before it is passed to the deallocator.
typedef void (*_Nonnull __cswiftslash_identified_list_iterator_f)(const uint64_t, const __cswiftslash_ptr_t, const __cswiftslash_optr_t);

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
/// @param __ indicates if this is a closing session (not to be confused with a session that may be zeroing).....meaning, the identified list will be freed from memory after the final element has been consumed from a freeing session. if true, you MUST call `__cswiftslash_identified_list_iterator_next_zero` until it returns NULL.
__cswiftslash_optr_t __cswiftslash_identified_list_iterator_register2(
	const __cswiftslash_identified_list_pair_ptr_t _,
	const bool __
);

/// @brief retrieves the next data pointer in the iteration sequence. NOTE: do not call this function if the iteration sequence has not been initiated with `__cswiftslash_identified_list_iterator_register`, or if this function has returned `false`.
/// @param _ the instance that is being iterated over. this must be the same instance used in the call to `__cswiftslash_identified_list_iterator_register`.
/// @param __ the pointer to store the next element in the iteration sequence. NOTE: you can only use this pointer to check for NULL. in such cases that the stored pointer is NULL, the iteration sequence has ended and the mutex will be unlocked.
/// @param ___ a pointer to store the key value associated with the data pointer.
/// @return the data pointer for the next element in the iteration sequence.
__cswiftslash_optr_t __cswiftslash_identified_list_iterator_next2(
	const __cswiftslash_identified_list_pair_ptr_t _,
	__cswiftslash_optr_t *_Nonnull __,
	uint64_t *_Nonnull ___
);

/// @brief retrieves the data data pointer in the iteration sequence and deallocates the element from the atomic list. NOTE: after calling this function (immediately after the first call to `__cswiftslash_identified_list_iterator_register`), you may not call `__cswiftslash_identified_list_iterator_next`. instead, you must call `__cswiftslash_identified_list_iterator_next_zero` until it returns NULL.
/// @param _ instance to iterate over.
/// @param __ the pointer to store the next element in the iteration sequence. NOTE: you can only use this pointer to check for NULL. in such cases that the stored pointer is NULL, the iteration sequence has ended and the mutex will be unlocked.
/// @param ___ the pointer to store the key value associated with the data pointer.
/// @param ____ should the identified list be closed after the iteration sequence has ended?
/// @return the data pointer for the next element in the iteration sequence.
__cswiftslash_optr_t __cswiftslash_identified_list_iterator_next_zero2(
	const __cswiftslash_identified_list_pair_ptr_t _,
	__cswiftslash_optr_t *_Nonnull __,
	uint64_t *_Nonnull ___,
	const bool ____
);

#endif // __CSWIFTSLASH_IDENTIFIED_LIST_H