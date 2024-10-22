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

pthread_mutex_t __cswiftslash_fifo_mutex_new() {
	pthread_mutex_t mutex;
	pthread_mutex_init(&mutex, NULL);
	return mutex;
}

__cswiftslash_fifo_linkpair_ptr_t __cswiftslash_fifo_init(pthread_mutex_t *_Nullable _) {
	if (_ != NULL) {

		// initialize WITH a mutex
		__cswiftslash_fifo_linkpair_t __0 = {
			.____bp = NULL,
			.____tp = NULL,
			.____ec = 0,
			.____ic = false,
			.____hm = true,
			.____m = *_,
			.____iwl = false,
			.____hme = false,
			.____me = 0
		};

		// the waiters mutex is always initialized.
		pthread_mutex_init(&__0.____wm, NULL);

		void *__1 = malloc(sizeof(__cswiftslash_fifo_linkpair_t));
		memcpy(__1, &_, sizeof(__cswiftslash_fifo_linkpair_t));

		return __1;
		
	} else {

		// initialize WITHOUT a mutex
		__cswiftslash_fifo_linkpair_t __0 = {
			.____bp = NULL,
			.____tp = NULL,
			.____ec = 0,
			.____ic = false,
			.____hm = false,
			.____iwl = false,
			.____hme = false,
			.____me = 0
		};

		// the waiters mutex is always initialized.
		pthread_mutex_init(&__0.____wm, NULL);

		void *__1 = malloc(sizeof(__cswiftslash_fifo_linkpair_t));
		memcpy(__1, &__0, sizeof(__cswiftslash_fifo_linkpair_t));

		return __1;
	}
}

bool __cswiftslash_fifo_set_max_elements(const __cswiftslash_fifo_linkpair_ptr_t _, const size_t __) {
	// this is the value that the function will return.
	bool __0 = false;

	// acquire the resource lock to synchronize the state of the chain.
	if (_->____hm) {
		pthread_mutex_lock(&_->____m);
	}

	// validate that the chain is not already capped.
	if (atomic_load_explicit(&_->____ic, memory_order_acquire) == true) {
		goto returnTime;
	}

	// do not cap the chain if there are already more elements than the new cap.
	if (atomic_load_explicit(&_->____ec, memory_order_acquire) > __) {
		goto returnTime;
	}

	// set the cap and store the max elements.
	atomic_store_explicit(&_->____hme, true, memory_order_release);
	atomic_store_explicit(&_->____me, __, memory_order_release);
	__0 = true;

	// cleans up the function and returns the result value to the caller.
	returnTime:
		if (_->____hm) {
			pthread_mutex_unlock(&_->____m);
		}
		return __0;
}

__cswiftslash_optr_t __cswiftslash_fifo_close(const __cswiftslash_fifo_linkpair_ptr_t _, const __cswiftslash_fifo_link_ptr_consume_f _Nullable __) {
	// load the base entry.
	__cswiftslash_fifo_link_ptr_t __0 = atomic_load_explicit(&_->____bp, memory_order_acquire);
	
	// place NULL at the base and tail so that others aren't able to manipulate the chain while we work to free it.
	atomic_store_explicit(&_->____bp, NULL, memory_order_release);
	atomic_store_explicit(&_->____tp, NULL, memory_order_release);
	
	// iterate through the chain and free all entries. call the deallocator function if it is not NULL.
	if (__ != NULL) {
		while (__0 != NULL) {
			__cswiftslash_fifo_link_ptr_t ____n = atomic_load_explicit(&__0->____n, memory_order_acquire);
			__(__0->____p);
			free(__0);
			__0 = ____n;
		}
	} else {
		while (__0 != NULL) {
			__cswiftslash_fifo_link_ptr_t ____n = atomic_load_explicit(&__0->____n, memory_order_acquire);
			free(__0);
			__0 = ____n;
		}
	}
	
	// destroy the mutexes if they exist.
	if (_->____hm) {
		pthread_mutex_destroy(&_->____m);
	}

	// unlock the waiters mutex if it is locked.
	if (atomic_load_explicit(&_->____iwl, memory_order_acquire) == true) {
		pthread_mutex_unlock(&_->____wm);
	}

	// destroy the waiters mutex.
	pthread_mutex_destroy(&_->____wm);

	// this will store the return value of the function.
	__cswiftslash_optr_t __1 = NULL;

	// return the cap pointer if the chain is capped.
	if (atomic_load_explicit(&_->____ic, memory_order_acquire) == true) {
		__1 = atomic_load_explicit(&_->____cp, memory_order_acquire);
	} else {
		__1 = NULL;
	}

	// free the chain structure.
	free(_);

	return __1;
}

bool __cswiftslash_fifo_pass_cap(const __cswiftslash_fifo_linkpair_ptr_t _, const __cswiftslash_optr_t __) {
	// this is the value that the function will return.
	bool __0 = false;

	// claim the internal sync mutex
	if (_->____hm) {
		pthread_mutex_lock(&_->____m);
	}

	bool __1 = false;	// we expect the chain to NOT be capped

	if (atomic_compare_exchange_weak_explicit(&_->____ic, &__1, true, memory_order_acq_rel, memory_order_relaxed)) {
		// successfully capped. now assign the capper pointer and store the number of remaining elements in the fifo.
		atomic_store_explicit(&_->____cp, __, memory_order_release);

		// if there are waiters, unlock the waiters mutex.
		if (atomic_load_explicit(&_->____iwl, memory_order_acquire) == true) {
			pthread_mutex_unlock(&_->____wm);
			atomic_store_explicit(&_->____iwl, false, memory_order_release);
		}

		// unlock the internal sync mutex
		__0 = true;
		goto returnTime;

	} else {

		// nothing to do, free the sync lock if it exists and then return
		__0 = false;
		goto returnTime;
	}

	returnTime:
		if (_->____hm) {
			pthread_mutex_unlock(&_->____m);
		}
		return __0;
}

bool ____cswiftslash_fifo_pass_link(const __cswiftslash_fifo_linkpair_ptr_t _, const __cswiftslash_fifo_link_ptr_t __) {
	// defines the value that we expect to find on the element we will append to. we must only append to the end of the chain, so we expect the next pointer to be NULL.
	__cswiftslash_fifo_link_ptr_t __0 = NULL;
	
	// load the current tail entry. it may exist, or it may not.
	__cswiftslash_fifo_link_ptr_t __1 = atomic_load_explicit(&_->____tp, memory_order_acquire);

	// determine where to try and write the new entry based on whether or not there is a tail entry.
	__cswiftslash_fifo_link_aptr_t*_Nonnull __2;
	__cswiftslash_fifo_link_aptr_t*_Nonnull __3;
	if (__1 == NULL) {
		__2 = &_->____tp;
		__3 = &_->____bp;
	} else {
		__2 = &__1->____n;
		__3 = &_->____tp;
	}

	// attempt to write the new entry to the chain.
	if (atomic_compare_exchange_weak_explicit(__2, &__0, __, memory_order_acq_rel, memory_order_relaxed)) {
		// swap successful, now write the secondary pointer if necessary.
		atomic_store_explicit(__3, __, memory_order_release);
		return true;
	} else {
		return false;
	}
}

int8_t __cswiftslash_fifo_pass(const __cswiftslash_fifo_linkpair_ptr_t _, const __cswiftslash_ptr_t __) {
	// the result of the operation will be stored here.
	int8_t __0 = -1;

	// lock the internal sync mutex if this instance is configured to use one.
	if (_->____hm) {
		pthread_mutex_lock(&_->____m);
	}

	// check if the chain is capped.
	if (atomic_load_explicit(&_->____ic, memory_order_acquire) == false) {
		// not capped. continue validation before adding.

		// verify that the maximum number of elements has not been reached.
		if (atomic_load_explicit(&_->____hme, memory_order_acquire) == true) {
			// max elements is set. check if the chain is full.
			if (atomic_load_explicit(&_->____ec, memory_order_acquire) >= atomic_load_explicit(&_->____me, memory_order_acquire)) {
				__0 = -2;
				goto returnTime;
			}
		}
		
		// create a new link to be added to the chain. this will be defined on the stack.
		const struct __cswiftslash_fifo_link __1 = {
			.____p = __,
			.____n = NULL
		};

		// copy the new link to the heap.
		const __cswiftslash_fifo_link_ptr_t __2 = memcpy(malloc(sizeof(struct __cswiftslash_fifo_link)), &__1, sizeof(struct __cswiftslash_fifo_link));

		// attempt to pass the link into the chain.
		if (____cswiftslash_fifo_pass_link(_, __2) == false) {
			// failure condition.
			free(__2);
			__0 = 1; // retry
			goto returnTime;
		}

		// the chain is not capped so we must increment the element count.
		atomic_fetch_add_explicit(&_->____ec, 1, memory_order_acq_rel);

		// signal any waiting threads that there is a new element in the chain.
		if (atomic_load_explicit(&_->____iwl, memory_order_acquire) == true) {
			pthread_mutex_unlock(&_->____wm);
			atomic_store_explicit(&_->____iwl, false, memory_order_release);
		}

		// success condition.
		__0 = 0;
		goto returnTime;
		
	} else {

		// the chain is capped. we cannot add any more elements.
		__0 = -1;
		goto returnTime;
	}

	returnTime:

		// unlock the internal sync mutex if this instance is configured to use one.
		if (_->____hm) {
			pthread_mutex_unlock(&_->____m);
		}

		// return the result of the operation.
		return __0;
}

/// internal function that flushes a single writer entry.
///	@param _ the pre-loaded atomic base pointer of the chain.
///	@param __: the chain that this operation will act on.
///	@param ___: the pointer that will be set to the consumed pointer.
/// - returns: true if the operation was successful and the element count could be decremented. false if the operation was not successful.
bool ____cswiftslash_fifo_consume_next(__cswiftslash_fifo_link_ptr_t _, const __cswiftslash_fifo_linkpair_ptr_t __, __cswiftslash_ptr_t *_Nonnull ___) {
	if (_ == NULL) {
		// there are no entries to consume.
		return false;
	}

	// load the next entry from the base.
	__cswiftslash_fifo_link_ptr_t __0 = atomic_load_explicit(&_->____n, memory_order_acquire);

	// attempt to pop the next entry from the _ by replacing the current base with the next entry.
	if (atomic_compare_exchange_weak_explicit(&__->____bp, &_, __0, memory_order_acq_rel, memory_order_relaxed)) {
		// successfully popped
		if (__0 == NULL) {
			// there are no more entries in the chain. write the tail to NULL to reflect this.
			atomic_store_explicit(&__->____tp, NULL, memory_order_release);
		}
		// decrement the atomic count to reflect the entry being consumed.
		atomic_fetch_sub_explicit(&__->____ec, 1, memory_order_acq_rel);
		*___ = _->____p;
		free((void*)_);
		return true;
	}
	return false;
}

__cswiftslash_fifo_consume_result_t __cswiftslash_fifo_consume_nonblocking(const __cswiftslash_fifo_linkpair_ptr_t _, __cswiftslash_optr_t *_Nonnull __) {
	// get exclusivity of the state.
	if (_->____hm) {
		pthread_mutex_lock(&_->____m);
	}

	__cswiftslash_fifo_consume_result_t __0;
	
	if (atomic_load_explicit(&_->____ec, memory_order_acquire) > 0) {

		// attempt to consume the next entry in the chain.
		if (____cswiftslash_fifo_consume_next(atomic_load_explicit(&_->____bp, memory_order_acquire), _, __)) {
			__0 = __CSWIFTSLASH_FIFO_CONSUME_RESULT;
			goto returnTime;
		} else {
			__0 = __CSWIFTSLASH_FIFO_CONSUME_INTERNAL_ERROR;
			goto returnTime;
		}

	} else {

		// check if the _ is capped.
		if (__builtin_expect(atomic_load_explicit(&_->____ic, memory_order_acquire) == false, true)){
			// no items and chain is NOT capped.
			__0 = __CSWIFTSLASH_FIFO_CONSUME_WOULDBLOCK;
			goto returnTime;
		} else {
			// the chain is capped. return the cap pointer.
			*__ = atomic_load_explicit(&_->____cp, memory_order_acquire);
			__0 = __CSWIFTSLASH_FIFO_CONSUME_CAP;
			goto returnTime;
		}

	}

	returnTime:
		// no longer need exclusivity of the state.
		if (_->____hm) {
			pthread_mutex_unlock(&_->____m);
		}
		return __0;
}

__cswiftslash_fifo_consume_result_t __cswiftslash_fifo_consume_blocking(const __cswiftslash_fifo_linkpair_ptr_t _, __cswiftslash_optr_t*_Nonnull __) {
	// used to determine if the waiters mutex was locked by this function during the course of its execution.
	bool __0 = false;
	
	loadAgain:
		// get exclusivity of the state.
		if (_->____hm) {
			pthread_mutex_lock(&_->____m);
		}

		// if this function was called before, we need to unlock the waiters mutex.
		if (__0 == true) {
			__0 = false;
			atomic_store_explicit(&_->____iwl, false, memory_order_release);
			pthread_mutex_unlock(&_->____wm);
		}

		// this is the code that will be returned when the function is done.
		__cswiftslash_fifo_consume_result_t __1;
		
		if (atomic_load_explicit(&_->____ec, memory_order_acquire) > 0) {
			// attempt to consume the next entry in the chain.
			if (____cswiftslash_fifo_consume_next(atomic_load_explicit(&_->____bp, memory_order_acquire), _, __)) {
				__1 = __CSWIFTSLASH_FIFO_CONSUME_RESULT;
				goto returnTime;
			} else {
				__1 = __CSWIFTSLASH_FIFO_CONSUME_INTERNAL_ERROR;
				goto returnTime;
			}
		} else {
			// check if the chain is capped.
			if (__builtin_expect(atomic_load_explicit(&_->____ic, memory_order_acquire) == false, true)) {
				// not capped, so we must wait for an element to be added.
				bool expectedLock = false;
				if (atomic_compare_exchange_weak_explicit(&_->____iwl, &expectedLock, true, memory_order_acq_rel, memory_order_relaxed)) {
					// acquire the waiters mutex. this should NOT block because there was no contention indicated in the atomic exchange.
					pthread_mutex_lock(&_->____wm);
				} else {
					abort();
				}
				// we can now free the internal sync mutex.
				if (_->____hm) {
					pthread_mutex_unlock(&_->____m);
				}
				goto blockForNext;
			} else {
				// the chain is capped. return the cap pointer.
				*__ = atomic_load_explicit(&_->____cp, memory_order_acquire);
				__1 = __CSWIFTSLASH_FIFO_CONSUME_CAP;
				goto returnTime;
			}
		}

	blockForNext:
		pthread_mutex_lock(&_->____wm);
		__0 = true;
		goto loadAgain;

	returnTime:

		// no longer need exclusivity of the state.
		if (_->____hm) {
			pthread_mutex_unlock(&_->____m);
		}
		return __1;
}