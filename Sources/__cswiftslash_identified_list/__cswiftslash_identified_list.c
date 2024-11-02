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
#define MAX_HASH_TABLE_SIZE 2097152
/// load factor threshold for resizing up (e.g., 0.75 means resize when 75% full).
#define RESIZE_UP_FACTOR 0.75
/// load factor threshold for resizing down (e.g., 0.25 means resize when 25% full).
#define RESIZE_DOWN_FACTOR 0.25
/// factor by which the hash table size increases upon resizing.
#define RESIZE_MULTIPLIER 2

// using knuth's multiplicative hash function
static size_t HF_(uint64_t key) {
    return (size_t)(key * 2654435761u);
}

/// function to resize the hash table.
/// must be called with mutex locked.
static void resize_hashtable(__cswiftslash_identified_list_pair_ptr_t list, size_t __) {
	__cswiftslash_identified_list_ptr_t* __0 = calloc(__, sizeof(__cswiftslash_identified_list_ptr_t));
	memset(__0, 0, __ * sizeof(__cswiftslash_identified_list_ptr_t));
	__cswiftslash_identified_list_ptr_t __1 = list->____o;
	while (__1 != NULL) {
		size_t __2 = HF_(__1->____k) % __;
		size_t __3 = 0;
		while (__0[__2] != NULL) {
			__3++;
			__2 = (__3 + 1) % __;
		}
		__0[__2] = __1;
		__1 = __1->____n;
	}
	free(list->____ht);
	list->____ht = __0;
	list->____hn = __;
}

__cswiftslash_identified_list_pair_t __cswiftslash_identified_list_init() {
	__cswiftslash_identified_list_pair_t __0 = {
		.____ht = calloc(INITIAL_HASH_TABLE_SIZE, sizeof(__cswiftslash_identified_list_ptr_t)),
		.____hn = INITIAL_HASH_TABLE_SIZE,
		.____i = 0,
		.____idi = 0,
		.____p = NULL,
		.____o = NULL
	};
	pthread_mutex_init(&__0.____m, NULL);
	return __0;
}

void __cswiftslash_identified_list_close(const __cswiftslash_identified_list_pair_ptr_t _, const __cswiftslash_identified_list_iterator_f __, const __cswiftslash_optr_t ___) {
	pthread_mutex_lock(&_->____m);
	
	// iterate through the hash table and free all entries.
	__cswiftslash_identified_list_ptr_t __0 = _->____o;
	while (__0 != NULL) {
		__(__0->____k, __0->____d, ___);
		__cswiftslash_identified_list_ptr_t __1 = __0;
		__0 = __0->____n;
		free(__1);
	}
	free(_->____ht);
	pthread_mutex_unlock(&_->____m);
	pthread_mutex_destroy(&_->____m);
}

uint64_t ____increment_overflow_guard(uint64_t *_Nonnull __) {
	if ((*__) == UINT64_MAX) {
		*__ = 1;
		return 1;
	}
	(*__)++;
	return *__;
}

uint64_t __cswiftslash_identified_list_insert(const __cswiftslash_identified_list_pair_ptr_t _, const __cswiftslash_ptr_t __) {
	pthread_mutex_lock(&_->____m);
	double __0 = (double)(_->____i + 1) / _->____hn;
	if (__0 > RESIZE_UP_FACTOR && _->____hn < MAX_HASH_TABLE_SIZE) {
		// resize up
		size_t __0_ = _->____hn * RESIZE_MULTIPLIER;
		if (__0_ > MAX_HASH_TABLE_SIZE) {
			__0_ = MAX_HASH_TABLE_SIZE;
		}
		resize_hashtable(_, __0_);
	}

	// generate a new unique key
	uint64_t __1 = ____increment_overflow_guard(&_->____idi);
	size_t __2 = HF_((size_t)__1) % _->____hn;
	size_t __3 = __2;
	size_t __4 = 0;

	// validate that this id is available in the hash table. if not, increment the hashed index until we find an empty slot
	while (_->____ht[__2] != NULL) {
		__4++;
		__2 = (__3 + __4) % _->____hn;
	}

	// create a new list node in the stack
	const __cswiftslash_identified_list_t __5 = {
		.____k = __1,
		.____d = __,
		.____n = NULL,
		.____p = _->____p
	};

	// allocate space for it in the heap
	__cswiftslash_identified_list_ptr_t __6 = malloc(sizeof(__cswiftslash_identified_list_t));
	memcpy(__6, &__5, sizeof(__cswiftslash_identified_list_t));

	// link into the hash table
	_->____ht[__2] = __6;

	// link into insertion order list
	if (_->____p != NULL) {
		_->____p->____n = __6;
	}
	_->____p = __6;
	if (_->____o == NULL) {
		_->____o = __6;
	}
	_->____i++;
	pthread_mutex_unlock(&_->____m);
	return __1;
}

__cswiftslash_optr_t __cswiftslash_identified_list_remove(const __cswiftslash_identified_list_pair_ptr_t _, const uint64_t __) {
	pthread_mutex_lock(&_->____m);
	size_t __0 = HF_((size_t)__) % _->____hn;
	const size_t __1 = __0;
	size_t __2 = 0;
	__cswiftslash_identified_list_ptr_t __node = NULL;

	// search for the node in the hash table
	while (_->____ht[__0] != NULL) {
		if (_->____ht[__0]->____k == __) {
			__node = _->____ht[__0];
			break;
		}
		__2++;
		__0 = (__1 + __2) % _->____hn;
	}

	// if the node is not found, return NULL
	if (__node == NULL) {
		pthread_mutex_unlock(&_->____m);
		return (__cswiftslash_optr_t)NULL;
	}

	// remove from the hash table
	_->____ht[__0] = NULL;

	// rehash subsequent nodes in the hash table
	__0 = (__0 + 1) % _->____hn;
	while (_->____ht[__0] != NULL) {
		__cswiftslash_identified_list_ptr_t __1 = _->____ht[__0];
		_->____ht[__0] = NULL;
		size_t __2 = HF_(__1->____k) % _->____hn;
		size_t __3 = __2;
		size_t __4 = 0;
		while (_->____ht[__2] != NULL) {
			__4++;
			__2 = (__3 + __4) % _->____hn;
		}
		_->____ht[__2] = __1;
		__0 = (__0 + 1) % _->____hn;
	}

	// remove from the insertion order list
	if (__node->____p != NULL) {
		__node->____p->____n = __node->____n;
	} else {
		_->____o = __node->____n;
	}

	if (__node->____n != NULL) {
		__node->____n->____p = __node->____p;
	} else {
		_->____p = __node->____p;
	}

	__cswiftslash_optr_t __4 = __node->____d;
	free(__node);
	_->____i--;

	// check if we need to resize down
	double __5 = (double)_->____i / _->____hn;
	if (__5 < RESIZE_DOWN_FACTOR && _->____hn > INITIAL_HASH_TABLE_SIZE) {
		size_t __6 = _->____hn / RESIZE_MULTIPLIER;
		if (__6 < INITIAL_HASH_TABLE_SIZE) {
			__6 = INITIAL_HASH_TABLE_SIZE;
		}
		resize_hashtable(_, __6);
	}
	
	pthread_mutex_unlock(&_->____m);
	return __4;
}

void __cswiftslash_identified_list_iterate(const __cswiftslash_identified_list_pair_ptr_t _, const __cswiftslash_identified_list_iterator_f __, const __cswiftslash_optr_t ___) {
	pthread_mutex_lock(&_->____m);
	__cswiftslash_identified_list_ptr_t __0 = _->____o;
	while (__0 != NULL) {
		__(__0->____k, __0->____d, ___);
		__0 = __0->____n;
	}
	pthread_mutex_unlock(&_->____m);
}

void __cswiftslash_identified_list_iterate_consume_zero(const __cswiftslash_identified_list_pair_ptr_t _, const __cswiftslash_identified_list_iterator_f __, const __cswiftslash_optr_t ___) {
	pthread_mutex_lock(&_->____m);
	__cswiftslash_identified_list_ptr_t __0 = _->____o;
	while (__0 != NULL) {
		__cswiftslash_identified_list_ptr_t __1 = __0->____n;
		__(__0->____k, __0->____d, ___);
		free(__0);
		__0 = __1;
	}
	_->____o = NULL;
	_->____p = NULL;
	_->____i = 0;
	pthread_mutex_unlock(&_->____m);
}