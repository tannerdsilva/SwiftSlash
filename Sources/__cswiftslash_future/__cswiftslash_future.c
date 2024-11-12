/*
LICENSE MIT
copyright (c) tanner silva 2024. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

#include "__cswiftslash_future.h"
#include "__cswiftslash_identified_list.h"

#include <stdatomic.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#ifdef DEBUG
#define CLIBSWIFTSLASH_PTRFUTURE_MAXLOOPS_SYNC 1
#endif

// status values.
typedef enum future_status {
	// pending status (future not fufilled).
	FUTURE_STATUS_PEND = 0,
	// result status (future fufilled normally).
	FUTURE_STATUS_RESULT = 1,
	// thrown status (future fufilled with an error).
	FUTURE_STATUS_THROW = 2,
	// cancel status (future was not fufilled and will NOT fufill in the future).
	FUTURE_STATUS_CANCEL = 3,
} _cswiftslash_future_status_t;

/// used to represent a thread that is synchronously waiting and blocking for the result of a future.
typedef struct __cswiftslash_future_wait_t {
	/// the context pointer that will be transparenly passed to the result handler.
	__cswiftslash_optr_t ____c;

	/// reflects the synchronous state of the future waiter. true for sync, false for async.
	const bool ____s;
	
	/// the mutex that is used to block the thread until the future is complete. this is only used if the waiter is synchronous.
	pthread_mutex_t ____m;

	/// the result handler to call when the future is complete.
	__cswiftslash_future_result_val_handler_f ____r;
	/// the error handler to call when the future is complete.
	__cswiftslash_future_result_err_handler_f ____e;
	/// the cancel handler to call when the future is cancelled and a result will never be available.
	__cswiftslash_future_result_cncl_handler_f ____v;
} __cswiftslash_future_wait_t;

struct ____cswiftslash_future_identified_list_tool {
	const uint8_t _;
	const __cswiftslash_optr_t __;
};

typedef __cswiftslash_future_wait_t *_Nonnull __cswiftslash_future_wait_ptr_t;

/// create a new synchronous waiter for a future.
/// @param _ the context pointer to pass to the result handler when it comes time to fire.
/// @param __ the handler to call when the future is complete with a valid result.
/// @param ___ the handler to call when the future is complete with an error.
/// @param ____ the handler to call when the future is cancelled and a result will never be available.
/// @return a pointer to the waiter structure on the heap.
__cswiftslash_future_wait_ptr_t ____cswiftslash_future_wait_t_init_sync(
	__cswiftslash_optr_t _,
	__cswiftslash_future_result_val_handler_f __,
	__cswiftslash_future_result_err_handler_f ___,
	__cswiftslash_future_result_cncl_handler_f ____
) {
	__cswiftslash_future_wait_t __0 = {
		.____c = _,
		.____s = true,
		.____r = __,
		.____e = ___,
		.____v = ____
	};
	if (pthread_mutex_init(&__0.____m, NULL) != 0) {
		printf("swiftslash future internal error: couldn't initialize future sync_wait mutex\n");
		abort();
	}
	__cswiftslash_future_wait_ptr_t __1 = malloc(sizeof(__cswiftslash_future_wait_t));
	memcpy(__1, &__0, sizeof(__cswiftslash_future_wait_t));
	return __1;
}

/// create a new asynchronous waiter for a future.
/// @param _ the context pointer to pass to the result handler when it comes time to fire.
/// @param __ the handler to call when the future is complete with a valid result.
/// @param ___ the handler to call when the future is complete with an error.
/// @param ____ the handler to call when the future is cancelled and a result will never be available.
/// @return the waiter structure.
__cswiftslash_future_wait_ptr_t ____cswiftslash_future_wait_t_init_async(__cswiftslash_optr_t _, __cswiftslash_future_result_val_handler_f __, __cswiftslash_future_result_err_handler_f ___, __cswiftslash_future_result_cncl_handler_f ____) {
	__cswiftslash_future_wait_t __0 = {
		.____c = _,
		.____s = false,
		.____r = (__cswiftslash_ptr_t)__,
		.____e = (__cswiftslash_ptr_t)___,
		.____v = (__cswiftslash_ptr_t)____
	};
	__cswiftslash_future_wait_ptr_t __1 = malloc(sizeof(__cswiftslash_future_wait_t));
	memcpy(__1, &__0, sizeof(__cswiftslash_future_wait_t));
	return __1;
}

void ____cswiftslash_future_wait_t_destroy_sync(__cswiftslash_future_wait_ptr_t _) {
	pthread_mutex_destroy(&_->____m);
	free((void*)_);
}
void ____cswiftslash_future_wait_t_destroy_async(__cswiftslash_future_wait_ptr_t _) {
	free((void*)_);
}

void ____cswiftslash_future_identified_list_cancel_iterator(
	const uint64_t _,
	const __cswiftslash_ptr_t __,
	const __cswiftslash_optr_t ___
) {
	if (((__cswiftslash_future_wait_ptr_t)__)->____s == true) {
		pthread_mutex_unlock(&((__cswiftslash_future_wait_ptr_t)__)->____m);
	} else {
		((__cswiftslash_future_wait_ptr_t)__)->____v(((__cswiftslash_future_wait_ptr_t)__)->____c);
		____cswiftslash_future_wait_t_destroy_async((__cswiftslash_future_wait_ptr_t)__);
	}
}

bool __cswiftslash_future_t_broadcast_cancel(
	const __cswiftslash_future_ptr_t _
) {	
	pthread_mutex_lock(&_->____m);
	uint8_t expected_complete = FUTURE_STATUS_PEND;
	if (atomic_compare_exchange_strong_explicit(&_->____s, &expected_complete, FUTURE_STATUS_CANCEL, memory_order_acq_rel, memory_order_relaxed) == false) {
		pthread_mutex_unlock(&_->____m);
		return false;
	}
	__cswiftslash_identified_list_iterate_consume_zero(_->____wi, ____cswiftslash_future_identified_list_cancel_iterator, NULL);
	pthread_mutex_unlock(&_->____m);
	return true;
}

void ____cswiftslash_future_identified_list_close(
	const uint64_t _,
	const __cswiftslash_ptr_t __,
	const __cswiftslash_ptr_t ___
) {
	free((void*)__);
}

__cswiftslash_future_ptr_t __cswiftslash_future_t_init() {
	__cswiftslash_future_ptr_t __0 = malloc(sizeof(__cswiftslash_future_t));
	atomic_store_explicit(&__0->____s, FUTURE_STATUS_PEND, memory_order_release);
	if (pthread_mutex_init(&__0->____m, NULL) != 0) {
		printf("swiftslash future internal error: couldn't initialize future mutex\n");
		abort();
	}
	__cswiftslash_identified_list_pair_t __1 = __cswiftslash_identified_list_init();
	__cswiftslash_ptr_t __2 = malloc(sizeof(__cswiftslash_identified_list_pair_t));
	memcpy(__2, &__1, sizeof(__cswiftslash_identified_list_pair_t));
	__0->____wi = __2;
	return __0;
}

void __cswiftslash_future_t_destroy(
	__cswiftslash_future_ptr_t _,
	const __cswiftslash_optr_t __,
	const _Nonnull __cswiftslash_future_result_val_handler_f ___,
	const _Nonnull __cswiftslash_future_result_err_handler_f ____
) {
	pthread_mutex_lock(&_->____m);
	int8_t __0 = atomic_load_explicit(&_->____s, memory_order_acquire);
	switch (__0) {
		case FUTURE_STATUS_PEND:
			__cswiftslash_identified_list_iterate_consume_zero(_->____wi, ____cswiftslash_future_identified_list_cancel_iterator, NULL);
			break;
		case FUTURE_STATUS_RESULT:
			___(atomic_load_explicit(&_->____rt, memory_order_acquire), atomic_load_explicit(&_->____rv, memory_order_acquire), __);
			break;
		case FUTURE_STATUS_THROW:
			____(atomic_load_explicit(&_->____rt, memory_order_acquire), atomic_load_explicit(&_->____rv, memory_order_acquire), __);
			break;
		default:
			printf("swiftslash future internal error: invalid future status\n");
			abort();
	}
	pthread_mutex_unlock(&_->____m);
	pthread_mutex_lock(&_->____m);
	__cswiftslash_identified_list_close(_->____wi, ____cswiftslash_future_identified_list_close, NULL);
	pthread_mutex_unlock(&_->____m);
	pthread_mutex_destroy(&_->____m);
	free(_);
}

void __cswiftslash_future_t_wait_sync(
	const __cswiftslash_future_ptr_t _,
	const __cswiftslash_optr_t __,
	const _Nonnull __cswiftslash_future_result_val_handler_f ___,
	const _Nonnull __cswiftslash_future_result_err_handler_f ____,
	const _Nonnull __cswiftslash_future_result_cncl_handler_f _____
) {
	pthread_mutex_lock(&_->____m);
	#ifdef DEBUG
	uint32_t __0 = 0;
	#endif
	__cswiftslash_future_wait_ptr_t __1 = ____cswiftslash_future_wait_t_init_sync(__, ___, ____, _____);
	pthread_mutex_lock(&__1->____m);
	uint8_t __2;
	__cswiftslash_optr_t __3;
	checkStat:
		switch (atomic_load_explicit(&_->____s, memory_order_acquire)) {
			case FUTURE_STATUS_PEND:
				__cswiftslash_identified_list_insert(_->____wi, __1);
				#ifdef DEBUG
				if (__0 >= CLIBSWIFTSLASH_PTRFUTURE_MAXLOOPS_SYNC) {
					printf("swiftslash future internal error: infinite loop detected in future wait\n");
					abort();
				}
				#endif
				goto blockUntilDone;
			case FUTURE_STATUS_RESULT:
				__2 = atomic_load_explicit(&_->____rt, memory_order_acquire);
				__3 = atomic_load_explicit(&_->____rv, memory_order_acquire);
				___(__2, __3, __);
				goto returnTime;	
			case FUTURE_STATUS_THROW:
				__2 = atomic_load_explicit(&_->____rt, memory_order_acquire);
				__3 = atomic_load_explicit(&_->____rv, memory_order_acquire);
				____(__2, __3, __);
				goto returnTime;
			case FUTURE_STATUS_CANCEL:
				_____(__);
				goto returnTime;
			default:
				printf("swiftslash future internal error: invalid future status\n");
				abort();
		}
	returnTime:
		pthread_mutex_unlock(&_->____m);
		pthread_mutex_unlock(&__1->____m);
		____cswiftslash_future_wait_t_destroy_sync(__1);
		return;
	blockUntilDone:
		#ifdef DEBUG
		__0 += 1;
		#endif
		pthread_mutex_unlock(&_->____m);
		pthread_mutex_lock(&__1->____m);
		pthread_mutex_lock(&_->____m);
		goto checkStat;
}

uint64_t __cswiftslash_future_t_wait_async(
	const __cswiftslash_future_ptr_t _,
	const __cswiftslash_optr_t __,
	const _Nonnull __cswiftslash_future_result_val_handler_f ___,
	const _Nonnull __cswiftslash_future_result_err_handler_f ____,
	const _Nonnull __cswiftslash_future_result_cncl_handler_f _____
) {
	const __cswiftslash_future_wait_ptr_t __0 = ____cswiftslash_future_wait_t_init_async(__, ___, ____, _____);
	pthread_mutex_lock(&_->____m);
	const int8_t __1 = atomic_load_explicit(&_->____s, memory_order_acquire);
	uint64_t __2;
	uint8_t __3;
	__cswiftslash_optr_t __4;
	checkStat:
	switch (__1) {
		case FUTURE_STATUS_PEND:
			__2 = __cswiftslash_identified_list_insert(_->____wi, (__cswiftslash_ptr_t)__0);
			goto returnTimeWaiting;
		case FUTURE_STATUS_RESULT:
			__3 = atomic_load_explicit(&_->____rt, memory_order_acquire);
			__4 = atomic_load_explicit(&_->____rv, memory_order_acquire);
			___(__3, __4, __);
			goto returnTimeNoWait;
		case FUTURE_STATUS_THROW:
			__3 = atomic_load_explicit(&_->____rt, memory_order_acquire);
			__4 = atomic_load_explicit(&_->____rv, memory_order_acquire);
			____(__3, __4, __);
			goto returnTimeNoWait;
		case FUTURE_STATUS_CANCEL:
			_____(NULL);
			goto returnTimeNoWait;
		default:
			printf("swiftslash future internal error: invalid future status\n");
			abort();
	}
	returnTimeNoWait:
		pthread_mutex_unlock(&_->____m);
		____cswiftslash_future_wait_t_destroy_async(__0);
		return 0;
	returnTimeWaiting:
		pthread_mutex_unlock(&_->____m);
		if (__2 == 0) {
			printf("swiftslash future internal error: future waiter should never have zero id. this is an internal error\n");
			abort();
		}
		return __2;
}

bool __cswiftslash_future_t_wait_async_invalidate(
	const __cswiftslash_future_ptr_t _,
	const uint64_t __
) {
	pthread_mutex_lock(&_->____m);
	const int8_t __0 = atomic_load_explicit(&_->____s, memory_order_acquire);
	__cswiftslash_optr_t __1;
	switch (__0) {
		case FUTURE_STATUS_PEND:
			goto cancelWaiter;
		case FUTURE_STATUS_RESULT:
			goto returnFalse;
		case FUTURE_STATUS_THROW:
			goto returnFalse;
		case FUTURE_STATUS_CANCEL:
			goto returnFalse;
		default:
			printf("swiftslash future internal error: invalid future status\n");
			abort();
	}
	cancelWaiter:
		__1 = __cswiftslash_identified_list_remove(_->____wi, __);
		pthread_mutex_unlock(&_->____m);
		if (__1 == NULL) {
			return false;
		}
		((__cswiftslash_future_wait_ptr_t)__1)->____v(((__cswiftslash_future_wait_ptr_t)(__1))->____c);
		____cswiftslash_future_wait_t_destroy_async(__1);
		return true;
	returnFalse:
		pthread_mutex_unlock(&_->____m);
		return false;
}

void ____cswiftslash_future_identified_list_val_iterator(
	const uint64_t _,
	const __cswiftslash_ptr_t wptr,
	const __cswiftslash_ptr_t ___
) {
	if (((__cswiftslash_future_wait_ptr_t)wptr)->____s == true) {
		pthread_mutex_unlock(&((__cswiftslash_future_wait_ptr_t)wptr)->____m);
	} else {
		((__cswiftslash_future_wait_ptr_t)wptr)->____r(((struct ____cswiftslash_future_identified_list_tool*)___)->_, ((struct ____cswiftslash_future_identified_list_tool*)___)->__, ((__cswiftslash_future_wait_ptr_t)wptr)->____c);
		____cswiftslash_future_wait_t_destroy_async((__cswiftslash_future_wait_ptr_t)wptr);
	}
}

void ____cswiftslash_future_identified_list_throw_iterator(
	const uint64_t _,
	const __cswiftslash_ptr_t wptr,
	const __cswiftslash_ptr_t ___
) {
	if (((__cswiftslash_future_wait_ptr_t)wptr)->____s == true) {
		pthread_mutex_unlock(&((__cswiftslash_future_wait_ptr_t)wptr)->____m);
	} else {
		((__cswiftslash_future_wait_ptr_t)wptr)->____e(((struct ____cswiftslash_future_identified_list_tool*)___)->_, ((struct ____cswiftslash_future_identified_list_tool*)___)->__, ((__cswiftslash_future_wait_ptr_t)wptr)->____c);
		____cswiftslash_future_wait_t_destroy_async((__cswiftslash_future_wait_ptr_t)wptr);
	}
}

bool __cswiftslash_future_t_broadcast_res_val(
	const __cswiftslash_future_ptr_t _,
	const uint8_t __,
	const __cswiftslash_optr_t ___
) {
	pthread_mutex_lock(&_->____m);
    uint8_t expected_complete = FUTURE_STATUS_PEND;
	if (atomic_compare_exchange_strong_explicit(&_->____s, &expected_complete, FUTURE_STATUS_RESULT, memory_order_acq_rel, memory_order_relaxed) == false) {
		pthread_mutex_unlock(&_->____m);
		return false;
	}
	atomic_store_explicit(&_->____rv, ___, memory_order_release);
	atomic_store_explicit(&_->____rt, __, memory_order_release);
	struct ____cswiftslash_future_identified_list_tool __0 = {
		._ = __,
		.__ = ___
	};
	__cswiftslash_identified_list_iterate_consume_zero(_->____wi, ____cswiftslash_future_identified_list_val_iterator, &__0);
	pthread_mutex_unlock(&_->____m);
	return true;
}

bool __cswiftslash_future_t_broadcast_res_throw(
	const __cswiftslash_future_ptr_t _,
	const uint8_t __,
	const __cswiftslash_optr_t ___
) {
	pthread_mutex_lock(&_->____m);
	uint8_t expected_complete = FUTURE_STATUS_PEND;
	if (atomic_compare_exchange_strong_explicit(&_->____s, &expected_complete, FUTURE_STATUS_THROW, memory_order_acq_rel, memory_order_relaxed) == false) {
		pthread_mutex_unlock(&_->____m);
		return false;
	}
	atomic_store_explicit(&_->____rv, ___, memory_order_release);
	atomic_store_explicit(&_->____rt, __, memory_order_release);
	struct ____cswiftslash_future_identified_list_tool __0 = {
		._ = __,
		.__ = ___
	};
	__cswiftslash_identified_list_iterate_consume_zero(_->____wi, ____cswiftslash_future_identified_list_throw_iterator, &__0);
	pthread_mutex_unlock(&_->____m);
	return true;
}