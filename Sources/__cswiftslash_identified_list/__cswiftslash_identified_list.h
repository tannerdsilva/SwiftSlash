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

/// forward declaration of the atomiclist structure. represents a single element in the atomic list.
struct __cswiftslash_identified_list;
/// defines a nullable pointer to a single element in the atomic list.
typedef struct __cswiftslash_identified_list* _Nullable __cswiftslash_identified_list_ptr_t;
/// defines an atomic pointer to a single element in the atomic list.
typedef _Atomic __cswiftslash_identified_list_ptr_t __cswiftslash_identified_list_aptr_t;
/// defines a non-null pointer to an atomic pointer to a single element in the atomic list.
typedef __cswiftslash_identified_list_aptr_t* _Nonnull __cswiftslash_identified_list_aptr_ptr_t;
/// consumer function prototype for processing data pointers in the atomic list. this is essentially the "last point of contact" for the data pointer before it is passed to the deallocator.
typedef void (*_Nonnull __cswiftslash_identified_list_ptr_f)(const uint64_t, const __cswiftslash_ptr_t, const __cswiftslash_ptr_t);

/// structure representing a single element within the atomic list.
typedef struct __cswiftslash_identified_list {
	/// the unique key value associated with the data pointer.
	const uint64_t key;
	/// the data pointer that the element instance is storing.
	const __cswiftslash_ptr_t ptr;
	/// the next element in the atomic list.
	__cswiftslash_identified_list_aptr_t next;
} __cswiftslash_identified_list_t;

/// primary storage container for the atomic list.
typedef struct __cswiftslash_identified_list_pair {
	/// the base storage slot for the list instance.
	__cswiftslash_identified_list_aptr_t base;
	/// the tail of the list, used for efficient addition of new elements.
	_Atomic size_t element_count;
	/// an internal value that increments with each new item added. this essentially represents the "next item's key"
	_Atomic uint64_t _id_increment_internal;
	/// the mutex that is used to keep the atomiclist in a consistent state
	pthread_mutex_t mutex;
} __cswiftslash_identified_list_pair_t;

/// defines a non-null pointer to an atomic list pair.
typedef __cswiftslash_identified_list_pair_t*_Nonnull __cswiftslash_identified_list_pair_ptr_t;

// initialization and deinitialization.

/// initializes a new atomic list pair instance.
/// @return a new atomic list pair instance. this instance must be deallocated with ``_cswiftslash_identified_list_close``
__cswiftslash_identified_list_pair_t __cswiftslash_identified_list_init();

/// deallocates memory of the atomic list pair instance. any remaining elements in the list will be deallocated.
/// @param list pointer to the atomic list pair instance to be deallocated.
/// @param consumer_f function used to process the data pointer before it is orphaned in the heap forever
/// @param ctx optional context pointer to be passed into the consumer function.
void __cswiftslash_identified_list_close(const __cswiftslash_identified_list_pair_ptr_t list, const __cswiftslash_identified_list_ptr_f consumer_f, const __cswiftslash_optr_t ctx);

// data handling.

/// inserts a new data pointer into the atomic list.
/// @param list pointer to the atomic list pair instance.
/// @param ptr pointer to the data to be stored in the atomic list.
/// @return the new key value associated with the data pointer.
uint64_t __cswiftslash_identified_list_insert(const __cswiftslash_identified_list_pair_ptr_t list, const __cswiftslash_ptr_t ptr);

/// removes a key (and its corresponding stored pointer) from the atomic list.
/// @param chain pointer to the atomic list pair instance.
/// @param key the key value of the element to be removed.
/// @return the data pointer that was removed from the atomic list. nil if the key was not found.
__cswiftslash_optr_t __cswiftslash_identified_list_remove(const __cswiftslash_identified_list_pair_ptr_t chain, const uint64_t key);

/// iterate through all elements in the atomic list, processing each data pointer with the provided consumer function.
/// @param list pointer to the atomic list pair instance.
/// @param consumer_f function used to process each data pointer in the atomic list.
/// @param ctx context pointer to be passed into the consumer function.
void __cswiftslash_identified_list_iterate(const __cswiftslash_identified_list_pair_ptr_t list, const __cswiftslash_identified_list_ptr_f consumer_f, const __cswiftslash_optr_t ctx);

#endif // __CSWIFTSLASH_IDENTIFIED_LIST_H