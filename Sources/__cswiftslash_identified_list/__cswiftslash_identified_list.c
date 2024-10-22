/*
LICENSE MIT
copyright (c) tanner silva 2024. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

#include "__cswiftslash_identified_list.h"
#include "__cswiftslash_types.h"

#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>

/// initial size of the hash table.
#define INITIAL_HASH_TABLE_SIZE 16
/// maximum size of the hash table.
#define MAX_HASH_TABLE_SIZE 1024
/// load factor threshold for resizing up (e.g., 0.75 means resize when 75% full).
#define RESIZE_UP_FACTOR 0.75
/// load factor threshold for resizing down (e.g., 0.25 means resize when 25% full).
#define RESIZE_DOWN_FACTOR 0.25
/// factor by which the hash table size increases upon resizing.
#define RESIZE_MULTIPLIER 2
/// simple hash function to compute the index from the key.
static size_t HF_(size_t key, size_t table_size) {
	return key % table_size;
}

/// function to resize the hash table.
/// must be called with mutex locked.
static void resize_hashtable(__cswiftslash_identified_list_pair_ptr_t list, size_t _) {
	// allocate new hash table.
	__cswiftslash_identified_list_ptr_t* __0 = calloc(_, sizeof(__cswiftslash_identified_list_ptr_t));

	// rehash all elements into the new table.
	for (size_t __1 = 0; __1 < list->____hn; ++__1) {
		__cswiftslash_identified_list_ptr_t __2 = list->____ht[__1];
		while (__2 != NULL) {
			__cswiftslash_identified_list_ptr_t __3 = __2->____n;
			size_t __4 = HF_((size_t)__2->____k, _);
			// insert into new table.
			__2->____n = __0[__4];
			__0[__4] = __2;
			__2 = __3;
		}
	}

	// free old table and update list with new table.
	free(list->____ht);
	list->____ht = __0;
	list->____hn = _;
}

__cswiftslash_identified_list_pair_t __cswiftslash_identified_list_init() {
	__cswiftslash_identified_list_pair_t __0;
	__0.____hn = INITIAL_HASH_TABLE_SIZE;
	__0.____ht = calloc(__0.____hn, sizeof(__cswiftslash_identified_list_ptr_t));
	__0.____n = 0;
	__0.____idi = 1;
	pthread_mutex_init(&__0.____m, NULL);
	return __0;
}

void __cswiftslash_identified_list_close(const __cswiftslash_identified_list_pair_ptr_t _, const __cswiftslash_identified_list_ptr_f __, const __cswiftslash_optr_t ___) {
	pthread_mutex_lock(&_->____m);
	// iterate through the hash table and free all entries.
	for (size_t __0 = 0; __0 < _->____hn; ++__0) {
		__cswiftslash_identified_list_ptr_t __1 = _->____ht[__0];
		while (__1 != NULL) {
			const __cswiftslash_identified_list_ptr_t __2 = __1->____n;
			__(__1->____k, __1->____p, ___);
			free(__1);
			__1 = __2;
		}
	}
	free(_->____ht);
	pthread_mutex_unlock(&_->____m);
	pthread_mutex_destroy(&_->____m);
}

uint64_t __cswiftslash_identified_list_insert(const __cswiftslash_identified_list_pair_ptr_t _, const __cswiftslash_ptr_t __) {
	pthread_mutex_lock(&_->____m);
	uint64_t __0 = _->____idi++;

	// check if resizing up is needed.
	double __1 = (double)(_->____n + 1) / _->____hn;
	if (__1 > RESIZE_UP_FACTOR && _->____hn < MAX_HASH_TABLE_SIZE) {
		size_t new_size = _->____hn * RESIZE_MULTIPLIER;
		if (new_size > MAX_HASH_TABLE_SIZE) {
			new_size = MAX_HASH_TABLE_SIZE;
		}
		resize_hashtable(_, new_size);
	}

	// compute the hash index.
	size_t __2 = HF_((size_t)__0, _->____hn);

	// create a new list node.
	const __cswiftslash_identified_list_t __3 = {
		.____k = __0,
		.____p = __,
		.____n = _->____ht[__2]
	};

	// create a new list node.
	__cswiftslash_identified_list_ptr_t __4 = malloc(sizeof(__cswiftslash_identified_list_t));
	memcpy(__4, &__3, sizeof(__cswiftslash_identified_list_t));
	_->____ht[__2] = __4;
	_->____n++;

	pthread_mutex_unlock(&_->____m);
	return __0;
}

__cswiftslash_optr_t __cswiftslash_identified_list_remove(const __cswiftslash_identified_list_pair_ptr_t _, const uint64_t __) {
	pthread_mutex_lock(&_->____m);
	size_t __0 = HF_((size_t)__, _->____hn);
	__cswiftslash_identified_list_ptr_t* __1 = &_->____ht[__0];
	while (*__1 != NULL) {
		if ((*__1)->____k == __) {
			__cswiftslash_identified_list_ptr_t __2 = *__1;
			__cswiftslash_optr_t __3 = __2->____p;
			*__1 = __2->____n;
			free(__2);
			_->____n--;

			// check if resizing down is needed.
			double __4 = (double)_->____n / _->____hn;
			if (__4 < RESIZE_DOWN_FACTOR && _->____hn > INITIAL_HASH_TABLE_SIZE) {
				size_t __5 = _->____hn / RESIZE_MULTIPLIER;
				if (__5 < INITIAL_HASH_TABLE_SIZE) {
					__5 = INITIAL_HASH_TABLE_SIZE;
				}
				resize_hashtable(_, __5);
			}

			pthread_mutex_unlock(&_->____m);
			return __3;
		}
		__1 = &(*__1)->____n;
	}
	pthread_mutex_unlock(&_->____m);
	return (__cswiftslash_optr_t)NULL;
}

void __cswiftslash_identified_list_iterate(const __cswiftslash_identified_list_pair_ptr_t _, const __cswiftslash_identified_list_ptr_f __, const __cswiftslash_optr_t ___) {
	pthread_mutex_lock(&_->____m);
	for (size_t __0 = 0; __0 < _->____hn; ++__0) {
		__cswiftslash_identified_list_ptr_t __1 = _->____ht[__0];
		while (__1 != NULL) {
			__(__1->____k, __1->____p, ___);
			__1 = __1->____n;
		}
	}
	pthread_mutex_unlock(&_->____m);
}