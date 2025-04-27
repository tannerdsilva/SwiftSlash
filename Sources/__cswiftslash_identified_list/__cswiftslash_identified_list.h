/*
LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

#ifndef __CLIBSWIFTSLASH_IDENTIFIED_LIST_H
#define __CLIBSWIFTSLASH_IDENTIFIED_LIST_H

#include "__cswiftslash_types.h"

#include <pthread.h>
#include <stdint.h>
#include <stdbool.h>

/// forward declaration of the identified list structure.
struct __cswiftslash_identified_list;

/// nullable pointer to a single element in the atomic list.
typedef struct __cswiftslash_identified_list* _Nullable __cswiftslash_identified_list_ptr_t;
/// defines an atomic pointer to a single element in the atomic list.
typedef __cswiftslash_identified_list_ptr_t __cswiftslash_identified_list_ptr_t;
/// consumer function prototype for processing data pointers in the atomic list. this is essentially the "last point of contact" for the data pointer before it is passed to the deallocator.
typedef void (*_Nonnull __cswiftslash_identified_list_iterator_f)(const uint64_t, const __cswiftslash_ptr_t, const __cswiftslash_ptr_t);

/// structure representing a single element within the atomic list.
typedef struct __cswiftslash_identified_list {
	/// unique key value associated with the data pointer.
	const uint64_t ____k;
	/// data pointer that the element instance is storing.
	const __cswiftslash_ptr_t ____d;
	/// next element that was stored in the hash table.
	struct __cswiftslash_identified_list* _Nullable ____n;
	/// previous element that was stored in the hash table.
	struct __cswiftslash_identified_list* _Nullable ____p;
} __cswiftslash_identified_list_t;

/// primary storage container for the atomic list.
typedef struct __cswiftslash_identified_list_pair {
	/// hash table array of pointers to linked lists.
	__cswiftslash_identified_list_ptr_t* _Nonnull ____ht;
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
typedef __cswiftslash_identified_list_pair_t* _Nonnull __cswiftslash_identified_list_pair_ptr_t;

// initialization and deinitialization functions.

/// initializes a new atomic list pair instance.
/// @return a new atomic list pair instance. Must be deallocated with `__cswiftslash_identified_list_close`.
__cswiftslash_identified_list_pair_t __cswiftslash_identified_list_init();

/// deallocates memory of the atomic list pair instance.
/// any remaining elements in the list will be deallocated.
/// @param _ pointer to the atomic list pair instance to be deallocated.
/// @param __ function used to process the data pointer before deallocation.
/// @param ___ optional context pointer to be passed into the consumer function.
void __cswiftslash_identified_list_close(
	const __cswiftslash_identified_list_pair_ptr_t _,
	const __cswiftslash_identified_list_iterator_f __,
	const __cswiftslash_optr_t ___
);

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

/// iterates through all elements in the atomic list, processing each data pointer with the provided consumer function.
/// @param _ pointer to the atomic list pair instance.
/// @param __ function used to process each data pointer in the atomic list.
/// @param ___ context pointer to be passed into the consumer function.
/// @param ____ if true, the atomic list will remain locked after the iteration is complete.
void __cswiftslash_identified_list_iterate(
	const __cswiftslash_identified_list_pair_ptr_t _,
	const __cswiftslash_identified_list_iterator_f __,
	const __cswiftslash_optr_t ___,
	const bool ____
);

/// iterates through all elements in the atomic list, processing each data pointer with the provided consumer function. after each element is processed, the element is removed from the identified list.
/// @param _ pointer to the atomic list pair instance.
/// @param __ function used to process each data pointer in the atomic list.
/// @param ___ context pointer to be passed into the consumer function.
/// @param ____ if true, the atomic list will remain locked after the iteration is complete.
void __cswiftslash_identified_list_iterate_consume_zero(
	const __cswiftslash_identified_list_pair_ptr_t _,
	const __cswiftslash_identified_list_iterator_f __,
	const __cswiftslash_optr_t ___,
	const bool ____
);

/// iterate functions allow for the session lock to hang outside of the function. when this is called, the session lock is not released, and this function is used to complete the lock.
/// @param _ pointer to the atomic list pair instance.
void __cswiftslash_identified_list_iterate_hanginglock_complete(
	const __cswiftslash_identified_list_pair_ptr_t _
);

#endif // __CLIBSWIFTSLASH_IDENTIFIED_LIST_H