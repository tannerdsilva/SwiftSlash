/*
LICENSE MIT
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

__cswiftslash_fifo_linkpair_ptr_t __cswiftslash_fifo_init(
	const bool _
) {
	if (_ == true) {

		// initialize WITH a state mutex.
		__cswiftslash_fifo_linkpair_t __0 = {
			.____bp = NULL,
			.____tp = NULL,
			.____ec = 0,
			.____ic = false,
			.____hm = true,
			.____iwl = false,
			.____hme = false,
			.____me = 0
		};
		pthread_mutex_init(&__0.____m, NULL);
		pthread_mutex_init(&__0.____wm, NULL);

		void *__1 = malloc(sizeof(__cswiftslash_fifo_linkpair_t));
		memcpy(__1, &__0, sizeof(__cswiftslash_fifo_linkpair_t));

		return __1;
		
	} else {

		// initialize WITHOUT a state mutex
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
		pthread_mutex_init(&__0.____wm, NULL);

		void *__1 = malloc(sizeof(__cswiftslash_fifo_linkpair_t));
		memcpy(__1, &__0, sizeof(__cswiftslash_fifo_linkpair_t));
		return __1;
	}
}

bool __cswiftslash_fifo_set_max_elements(
	const __cswiftslash_fifo_linkpair_ptr_t _,
	const size_t __
) {
	bool __0 = false;
	if (_->____hm == true) {
		pthread_mutex_lock(&_->____m);
	}
	if (atomic_load_explicit(&_->____ic, memory_order_acquire) == true) {
		goto returnTime;
	}
	if (atomic_load_explicit(&_->____ec, memory_order_acquire) > __) {
		goto returnTime;
	}
	atomic_store_explicit(&_->____hme, true, memory_order_release);
	atomic_store_explicit(&_->____me, __, memory_order_release);
	__0 = true;
	returnTime:
		if (_->____hm == true) {
			pthread_mutex_unlock(&_->____m);
		}
		return __0;
}

__cswiftslash_optr_t __cswiftslash_fifo_close(
	const __cswiftslash_fifo_linkpair_ptr_t _,
	const __cswiftslash_fifo_link_ptr_consume_f _Nullable __
) {
	__cswiftslash_fifo_link_ptr_t __0 = atomic_load_explicit(&_->____bp, memory_order_acquire);
	atomic_store_explicit(&_->____bp, NULL, memory_order_release);
	atomic_store_explicit(&_->____tp, NULL, memory_order_release);
	if (__ != NULL) {
		while (__0 != NULL) {
			__cswiftslash_fifo_link_ptr_t __1 = atomic_load_explicit(&__0->__, memory_order_acquire);
			__(__0->_);
			free(__0);
			__0 = __1;
		}
	} else {
		while (__0 != NULL) {
			__cswiftslash_fifo_link_ptr_t __1 = atomic_load_explicit(&__0->__, memory_order_acquire);
			free(__0);
			__0 = __1;
		}
	}
	if (_->____hm == true) {
		pthread_mutex_destroy(&_->____m);
	}
	if (atomic_load_explicit(&_->____iwl, memory_order_acquire) == true) {
		pthread_mutex_unlock(&_->____wm);
	}
	pthread_mutex_destroy(&_->____wm);
	__cswiftslash_optr_t __1 = NULL;
	if (atomic_load_explicit(&_->____ic, memory_order_acquire) == true) {
		__1 = atomic_load_explicit(&_->____cp, memory_order_acquire);
	} else {
		__1 = NULL;
	}
	free(_);
	return __1;
}

bool __cswiftslash_fifo_pass_cap(
	const __cswiftslash_fifo_linkpair_ptr_t _,
	const __cswiftslash_optr_t __
) {
	bool __0 = false;
	if (_->____hm == true) {
		pthread_mutex_lock(&_->____m);
	}
	bool __1 = false;
	if (atomic_compare_exchange_weak_explicit(&_->____ic, &__1, true, memory_order_acq_rel, memory_order_relaxed) == true) {
		atomic_store_explicit(&_->____cp, __, memory_order_release);
		if (atomic_load_explicit(&_->____iwl, memory_order_acquire) == true) {
			pthread_mutex_unlock(&_->____wm);
			atomic_store_explicit(&_->____iwl, false, memory_order_release);
		}
		__0 = true;
		goto returnTime;
	} else {
		__0 = false;
		goto returnTime;
	}
	returnTime:
		if (_->____hm == true) {
			pthread_mutex_unlock(&_->____m);
		}
		return __0;
}

bool ____cswiftslash_fifo_pass_link(
	const __cswiftslash_fifo_linkpair_ptr_t _,
	const __cswiftslash_fifo_link_ptr_t __
) {
	__cswiftslash_fifo_link_ptr_t __0 = NULL;
	__cswiftslash_fifo_link_ptr_t __1 = atomic_load_explicit(&_->____tp, memory_order_acquire);
	__cswiftslash_fifo_link_aptr_t*_Nonnull __2;
	__cswiftslash_fifo_link_aptr_t*_Nonnull __3;
	if (__1 == NULL) {
		__2 = &_->____tp;
		__3 = &_->____bp;
	} else {
		__2 = &__1->__;
		__3 = &_->____tp;
	}
	if (atomic_compare_exchange_weak_explicit(__2, &__0, __, memory_order_acq_rel, memory_order_relaxed) == true) {
		atomic_store_explicit(__3, __, memory_order_release);
		return true;
	} else {
		return false;
	}
}

int8_t __cswiftslash_fifo_pass(
	const __cswiftslash_fifo_linkpair_ptr_t _,
	const __cswiftslash_ptr_t __
) {
	int8_t __0 = -1;
	if (_->____hm == true) {
		pthread_mutex_lock(&_->____m);
	}
	if (atomic_load_explicit(&_->____ic, memory_order_acquire) == false) {
		if (atomic_load_explicit(&_->____hme, memory_order_acquire) == true) {
			if (atomic_load_explicit(&_->____ec, memory_order_acquire) >= atomic_load_explicit(&_->____me, memory_order_acquire)) {
				__0 = -2;
				goto returnTime;
			}
		}
		const struct __cswiftslash_fifo_link __1 = {
			._ = __,
			.__ = NULL
		};
		const __cswiftslash_fifo_link_ptr_t __2 = memcpy(malloc(sizeof(struct __cswiftslash_fifo_link)), &__1, sizeof(struct __cswiftslash_fifo_link));
		if (____cswiftslash_fifo_pass_link(_, __2) == false) {
			free(__2);
			__0 = 1;
			goto returnTime;
		}
		atomic_fetch_add_explicit(&_->____ec, 1, memory_order_acq_rel);
		if (atomic_load_explicit(&_->____iwl, memory_order_acquire) == true) {
			pthread_mutex_unlock(&_->____wm);
			atomic_store_explicit(&_->____iwl, false, memory_order_release);
		}
		__0 = 0;
		goto returnTime;
	} else {
		__0 = -1;
		goto returnTime;
	}
	returnTime:
		if (_->____hm == true) {
			pthread_mutex_unlock(&_->____m);
		}
		return __0;
}

/// internal function that flushes a single writer entry.
///	@param _ the pre-loaded atomic base pointer of the chain.
///	@param __: the chain that this operation will act on.
///	@param ___: the pointer that will be set to the consumed pointer.
/// - returns: true if the operation was successful and the element count could be decremented. false if the operation was not successful.
bool ____cswiftslash_fifo_consume_next(
	__cswiftslash_fifo_link_ptr_t _,
	const __cswiftslash_fifo_linkpair_ptr_t __,
	__cswiftslash_ptr_t *_Nonnull ___
) {
	if (_ == NULL) {
		return false;
	}
	__cswiftslash_fifo_link_ptr_t __0 = atomic_load_explicit(&_->__, memory_order_acquire);
	if (atomic_compare_exchange_weak_explicit(&__->____bp, &_, __0, memory_order_acq_rel, memory_order_relaxed) == true) {
		if (__0 == NULL) {
			atomic_store_explicit(&__->____tp, NULL, memory_order_release);
		}
		atomic_fetch_sub_explicit(&__->____ec, 1, memory_order_acq_rel);
		*___ = _->_;
		free((void*)_);
		return true;
	}
	return false;
}

__cswiftslash_fifo_consume_result_t __cswiftslash_fifo_consume_nonblocking(
	const __cswiftslash_fifo_linkpair_ptr_t _,
	__cswiftslash_optr_t *_Nonnull __
) {
	if (_->____hm == true) {
		pthread_mutex_lock(&_->____m);
	}
	__cswiftslash_fifo_consume_result_t __0;
	if (atomic_load_explicit(&_->____ec, memory_order_acquire) > 0) {
		if (____cswiftslash_fifo_consume_next(atomic_load_explicit(&_->____bp, memory_order_acquire), _, __) == true) {
			__0 = __CSWIFTSLASH_FIFO_CONSUME_RESULT;
			goto returnTime;
		} else {
			__0 = __CSWIFTSLASH_FIFO_CONSUME_INTERNAL_ERROR;
			goto returnTime;
		}
	} else {
		if (atomic_load_explicit(&_->____ic, memory_order_acquire) == false){
			__0 = __CSWIFTSLASH_FIFO_CONSUME_WOULDBLOCK;
			goto returnTime;
		} else {
			*__ = atomic_load_explicit(&_->____cp, memory_order_acquire);
			__0 = __CSWIFTSLASH_FIFO_CONSUME_CAP;
			goto returnTime;
		}
	}
	returnTime:
		if (_->____hm == true) {
			pthread_mutex_unlock(&_->____m);
		}
		return __0;
}

__cswiftslash_fifo_consume_result_t __cswiftslash_fifo_consume_blocking(
	const __cswiftslash_fifo_linkpair_ptr_t _,
	__cswiftslash_optr_t*_Nonnull __
) {
	bool __0 = false;
	loadAgain:
		if (_->____hm == true) {
			pthread_mutex_lock(&_->____m);
		}
		if (__0 == true) {
			__0 = false;
			atomic_store_explicit(&_->____iwl, false, memory_order_release);
			pthread_mutex_unlock(&_->____wm);
		}
		__cswiftslash_fifo_consume_result_t __1;
		if (atomic_load_explicit(&_->____ec, memory_order_acquire) > 0) {
			if (____cswiftslash_fifo_consume_next(atomic_load_explicit(&_->____bp, memory_order_acquire), _, __)) {
				__1 = __CSWIFTSLASH_FIFO_CONSUME_RESULT;
				goto returnTime;
			} else {
				__1 = __CSWIFTSLASH_FIFO_CONSUME_INTERNAL_ERROR;
				goto returnTime;
			}
		} else {
			if (atomic_load_explicit(&_->____ic, memory_order_acquire) == false) {
				bool __2 = false;
				if (atomic_compare_exchange_weak_explicit(&_->____iwl, &__2, true, memory_order_acq_rel, memory_order_relaxed)) {
					pthread_mutex_lock(&_->____wm);
				} else {
					abort();
				}
				if (_->____hm) {
					pthread_mutex_unlock(&_->____m);
				}
				goto blockForNext;
			} else {
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
		if (_->____hm) {
			pthread_mutex_unlock(&_->____m);
		}
		return __1;
}