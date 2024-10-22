/*
LICENSE MIT
copyright (c) tanner silva 2024. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

#include "__cswiftslash_future.h"
#include "__cswiftslash_fifo.h"

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
	// pending status (future not fufilled)
	FUTURE_STATUS_PEND = 0,
	// result status (future fufilled normally)
	FUTURE_STATUS_RESULT = 1,
	// thrown status (future fufilled with an error)
	FUTURE_STATUS_THROW = 2,
	// cancel status (future was not fufilled and will NOT fufill in the future)
	FUTURE_STATUS_CANCEL = 3,
} _cswiftslash_future_status_t;


/// used to represent a thread that is synchronously waiting and blocking for the result of a future.
typedef struct __cswiftslash_future_wait_t {
	/// the context pointer that will be transparenly passed to the result handler.
	__cswiftslash_optr_t ____c;

	/// if the waiter is synchronous, this will be true.
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

/// a pointer to a future waiter.
typedef __cswiftslash_future_wait_t *_Nonnull __cswiftslash_future_wait_ptr_t;

/// create a new synchronous waiter for a future.
/// @param _ the context pointer to pass to the result handler when it comes time to fire.
/// @param __ the handler to call when the future is complete with a valid result.
/// @param ___ the handler to call when the future is complete with an error.
/// @param ____ the handler to call when the future is cancelled and a result will never be available.
/// @return a pointer to the waiter structure on the heap.
__cswiftslash_future_wait_ptr_t ____cswiftslash_future_wait_t_init_sync(__cswiftslash_optr_t _, __cswiftslash_future_result_val_handler_f __, __cswiftslash_future_result_err_handler_f ___, __cswiftslash_future_result_cncl_handler_f ____) {
	// declare the new structure value on the stack.
	__cswiftslash_future_wait_t __0 = {
		.____c = _,
		.____s = true,
		.____r = __,
		.____e = ___,
		.____v = ____
	};

	// initialize a new mutex onto the stack space.
	if (pthread_mutex_init(&__0.____m, NULL) != 0) {
		// fatal error. this would be a bug.
		printf("swiftslash future internal error: couldn't initialize future sync_wait mutex\n");
		abort();
	}

	// copy the waiter to the heap.
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
	// create a new waiter structure in the stack.
	__cswiftslash_future_wait_t __0 = {
		.____c = _,
		.____s = false,
		.____r = (__cswiftslash_ptr_t)__,
		.____e = (__cswiftslash_ptr_t)___,
		.____v = (__cswiftslash_ptr_t)____
	};

	// no mutex to initialize for async waiters.

	// copy the waiter to the heap.
	__cswiftslash_future_wait_ptr_t __1 = malloc(sizeof(__cswiftslash_future_wait_t));
	memcpy(__1, &__0, sizeof(__cswiftslash_future_wait_t));

	// return the heap waiter.
	return __1;
}

void ____cswiftslash_future_wait_t_destroy_sync(__cswiftslash_future_wait_ptr_t _) {
	// destroy the mutex for the sync_wait stack.
	pthread_mutex_destroy(&_->____m);

	// free the memory from the heap.
	free((void*)_);
}

void ____cswiftslash_future_wait_t_destroy_async(__cswiftslash_future_wait_ptr_t _) {
	// free the heap pointer from memory
	free((void*)_);
}

bool ____cswiftslash_future_t_broadcast_cancel(const _cswiftslash_future_ptr_t _) {	
	// flip the status from pending to successfully fufilled.
	uint8_t __0 = FUTURE_STATUS_PEND;
	if (atomic_compare_exchange_strong_explicit(&_->____s, &__0, FUTURE_STATUS_CANCEL, memory_order_acq_rel, memory_order_relaxed) == false) {
		// the item was not the expected value and therefore NOT assigned.
		// this means that someone else is working to close the structure, so we should return failure and do nothing (dont want to double close).
		return false;
	}

	// other threads may have been waiting on this result. notify the waiters.
	__cswiftslash_optr_t __1; // each waiter is stored here as the fifo pipeline is consumed.
	while (__cswiftslash_fifo_consume_nonblocking(_->____w, &__1) == 0) {
		// fire the result handler function any and all waiters.
		if (((__cswiftslash_future_wait_ptr_t)__1)->____s == true) {
			// this is a synchronous waiter. we can unlock their mutex and move on.
			pthread_mutex_unlock(&((__cswiftslash_future_wait_ptr_t)__1)->____m);
		} else {
			((__cswiftslash_future_wait_ptr_t)__1)->____v(((__cswiftslash_future_wait_ptr_t)__1)->____c);
			// free the heap pointer from memory
			____cswiftslash_future_wait_t_destroy_async((__cswiftslash_future_wait_ptr_t)__1);
		}
	}

	return true;
}

/// this is an internal function used to close the future waiters fifo.
/// @param _ the pointer to a waiter info structure that should be freed.
void ____cswiftslash_future_fifo_close(void *_Nonnull _) {
	printf("swiftslash future internal error: future waiter fifo was closed while containing waiters. this should be mechanically impossible - this is a bug\n");
	abort();
}

_cswiftslash_future_ptr_t __cswiftslash_future_t_init(void) {
	_cswiftslash_future_ptr_t __0 = malloc(sizeof(__cswiftslash_future_t));
	atomic_store_explicit(&__0->____s, FUTURE_STATUS_PEND, memory_order_release);

	if (pthread_mutex_init(&__0->____m, NULL) != 0) {
		// fatal error. this would be a bug.
		printf("swiftslash future internal error: couldn't initialize future mutex\n");
		abort();
	}

	__0->____w = __cswiftslash_fifo_init(NULL);

	// return the stack space
	return __0;
}

void __cswiftslash_future_t_destroy(
	_cswiftslash_future_ptr_t _,
	const __cswiftslash_optr_t __,
	const _Nonnull __cswiftslash_future_result_val_handler_f ___,
	const _Nonnull __cswiftslash_future_result_err_handler_f ____
) {
	// lock the internal state of the future to set the state to cancelled (if it needs to be).
	pthread_mutex_lock(&_->____m);
	int8_t curstat = atomic_load_explicit(&_->____s, memory_order_acquire);
	switch (curstat) {
		case FUTURE_STATUS_PEND:
			if (____cswiftslash_future_t_broadcast_cancel(_) == false) {
				printf("swiftslash future internal error: couldn't cancel future\n");
				abort();
			}
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

	// destroy the fifo of waiters.
	pthread_mutex_lock(&_->____m);
	__cswiftslash_fifo_close(_->____w, ____cswiftslash_future_fifo_close);
	pthread_mutex_unlock(&_->____m);

	// destroy the memory.
	pthread_mutex_destroy(&_->____m);
	free(_);
}

void __cswiftslash_future_t_wait_sync(
	const _cswiftslash_future_ptr_t _,
	const __cswiftslash_optr_t __,
	const _Nonnull __cswiftslash_future_result_val_handler_f ___,
	const _Nonnull __cswiftslash_future_result_err_handler_f ____,
	const _Nonnull __cswiftslash_future_result_cncl_handler_f _____
) {

	// lock the future mutex so that the structure can be kept in a consistent state.
	pthread_mutex_lock(&_->____m);

	#ifdef DEBUG
	// this is a theoretical possibility for this function to infinite loop (although this should be impossible in practice, unless there is a bug). this code takes the extra compute headroom of the debug build config to verify this is not the case.
	uint32_t __0 = 0;
	#endif

	__cswiftslash_future_wait_ptr_t __1 = ____cswiftslash_future_wait_t_init_sync(__, ___, ____, _____);
	pthread_mutex_lock(&__1->____m);

	checkStat:	// goto checkStat requires the local and global locks to be held.

	// acquire the status of the future.
	switch (atomic_load_explicit(&_->____s, memory_order_acquire)) {
		case FUTURE_STATUS_PEND:

			// broadcast our thread as a waiter.
			if (__cswiftslash_fifo_pass(_->____w, (__cswiftslash_ptr_t)__1) != 0) {

				// internal fatal error. this would be a bug
				printf("swiftslash future internal error: couldn't insert waiter into the queue\n");
				abort();
			}

			#ifdef DEBUG
			if (__0 >= CLIBSWIFTSLASH_PTRFUTURE_MAXLOOPS_SYNC) {
				// we have looped at least once. this is a bug.
				printf("swiftslash future internal error: infinite loop detected in future wait\n");
				abort();
			}
			#endif
			
			// wait for something to come back.
			goto blockUntilDone;

		case FUTURE_STATUS_RESULT:
			// the future is fufilled with a result.
			
			// fire the result handler.
			___(atomic_load_explicit(&_->____rt, memory_order_acquire), atomic_load_explicit(&_->____rv, memory_order_acquire), __);

			goto returnTime;

		case FUTURE_STATUS_THROW:
			// the future is fufilled with an error.

			// fire the error handler.
			____(atomic_load_explicit(&_->____rt, memory_order_acquire), atomic_load_explicit(&_->____rv, memory_order_acquire), __);

			goto returnTime;

		case FUTURE_STATUS_CANCEL:
			// the future was cancelled. fire the handler and exit.
			_____(__);
			
			goto returnTime;
		
		default:
			printf("swiftslash future internal error: invalid future status\n");
			abort();
	}

	returnTime:	// goto returnTime requires the local and global locks to be held.

		// no longer need to be synchronized with the global memory, lets free that first.
		pthread_mutex_unlock(&_->____m);
		// unlock the local lock.
		pthread_mutex_unlock(&__1->____m);
		// destroy the local waiter.
		____cswiftslash_future_wait_t_destroy_sync(__1);

		return; // cleanup complete, return to the caller.

	blockUntilDone:	// goto blockUntilDone requires the local and global locks to be held.

		#ifdef DEBUG
		// document that we have looped one time.
		__0 += 1;
		#endif

		// remove the lock which keeps us synchronized with the global memory of the future.
		pthread_mutex_unlock(&_->____m);
		// wait for the result to be broadcasted.
		pthread_mutex_lock(&__1->____m);
		// relock the global memory of the future.
		pthread_mutex_lock(&_->____m);
		
		goto checkStat;	// recheck the status of the future with both locks acquired.
}

void __cswiftslash_future_t_wait_async(
	const _cswiftslash_future_ptr_t _,
	const __cswiftslash_optr_t __,
	const _Nonnull __cswiftslash_future_result_val_handler_f ___,
	const _Nonnull __cswiftslash_future_result_err_handler_f ____,
	const _Nonnull __cswiftslash_future_result_cncl_handler_f _____
) {
	// create a new waiter for this future.
	__cswiftslash_future_wait_ptr_t waiterHeap = ____cswiftslash_future_wait_t_init_async(__, ___, ____, _____);

	// acquire the global lock for this instance.
	pthread_mutex_lock(&_->____m);

	// load the state of the future.
	int8_t curstat = atomic_load_explicit(&_->____s, memory_order_acquire);

	checkStat:
	switch (curstat) {
		case FUTURE_STATUS_PEND:

			// broadcast our thread as a waiter.
			if (__cswiftslash_fifo_pass(_->____w, (__cswiftslash_ptr_t)waiterHeap) != 0) {
				// internal fatal error. this would be a bug
				printf("swiftslash future internal error: couldn't insert waiter into the queue\n");
				abort();
			}

			goto returnTimeWaiting;

		case FUTURE_STATUS_RESULT:
			// the future is fufilled with a result.
			
			// fire the result handler.
			___(atomic_load_explicit(&_->____rt, memory_order_acquire), atomic_load_explicit(&_->____rv, memory_order_acquire), __);

			goto returnTimeNoWait;

		case FUTURE_STATUS_THROW:
			// the future is fufilled with an error.

			// fire the error handler.
			____(atomic_load_explicit(&_->____rt, memory_order_acquire), atomic_load_explicit(&_->____rv, memory_order_acquire), __);

			goto returnTimeNoWait;

		case FUTURE_STATUS_CANCEL:
			// the future was cancelled. fire the handler and exit.
			
			// fire the cancel handler.
			_____(NULL);
			
			goto returnTimeNoWait;
		
		default:
			printf("swiftslash future internal error: invalid future status\n");
			abort();
	}

	returnTimeNoWait:
		// a result was immediately available, so we can free the memory and return.

		// unlock the global lock.
		pthread_mutex_unlock(&_->____m);

		// free the local waiter.
		____cswiftslash_future_wait_t_destroy_async(waiterHeap);
		return;

	returnTimeWaiting:
		// the future is not yet complete, so we must not free the newly allocated memory.

		// unlock the global lock.
		pthread_mutex_unlock(&_->____m);
		return;
}

bool __cswiftslash_future_t_broadcast_res_val(const _cswiftslash_future_ptr_t _, const uint8_t __, const __cswiftslash_optr_t ___) {
	// acquire the global lock for synchronization.
	pthread_mutex_lock(&_->____m);

	// flip the status from pending to successfully fufilled.
    uint8_t expected_complete = FUTURE_STATUS_PEND;
	if (atomic_compare_exchange_strong_explicit(&_->____s, &expected_complete, FUTURE_STATUS_RESULT, memory_order_acq_rel, memory_order_acquire) == false) {
		// the item was not the expected value and therefore NOT assigned.
		// this means that someone else is working to close the structure, so we should return failure and do nothing (dont want to double close).
		goto returnFailure;
	}

	// store the result values.
	atomic_store_explicit(&_->____rv, ___, memory_order_release);
	atomic_store_explicit(&_->____rt, __, memory_order_release);

	// broadcast the result to all waiters.
	__cswiftslash_optr_t wptr;
	while (__cswiftslash_fifo_consume_nonblocking(_->____w, &wptr) == __CSWIFTSLASH_FIFO_CONSUME_RESULT) {
		// fire the result handler function any and all waiters.
		if (((__cswiftslash_future_wait_ptr_t)wptr)->____s == true) {
			// this is a synchronous waiter. we can unlock their mutex and move on.
			pthread_mutex_unlock(&((__cswiftslash_future_wait_ptr_t)wptr)->____m);
		} else {
			// fire the async handler. there is no mutex to handle in this scenario.
			((__cswiftslash_future_wait_ptr_t)wptr)->____r(__, ___, ((__cswiftslash_future_wait_ptr_t)wptr)->____c);
			// free the heap pointer from memory
			____cswiftslash_future_wait_t_destroy_async((__cswiftslash_future_wait_ptr_t)wptr);
		}
	}

	goto returnSuccess;

	returnSuccess:
		// return true, since we successfully broadcasted the result.
		pthread_mutex_unlock(&_->____m);
		return true;

	returnFailure:
		// return false, since we failed to broadcast the result.
		pthread_mutex_unlock(&_->____m);
		return false;
}

bool __cswiftslash_future_t_broadcast_res_throw(const _cswiftslash_future_ptr_t _, const uint8_t __, const __cswiftslash_optr_t ___) {
	// acquire the global lock for synchronization.
	pthread_mutex_lock(&_->____m);
	
	// flip the status from pending to successfully fufilled.
	uint8_t expected_complete = FUTURE_STATUS_PEND;
	if (atomic_compare_exchange_strong_explicit(&_->____s, &expected_complete, FUTURE_STATUS_THROW, memory_order_acq_rel, memory_order_acquire) == false) {
		// the item was not the expected value and therefore NOT assigned.
		// this means that someone else is working to close the structure, so we should return failure and do nothing (dont want to double close).
		goto returnFailure;
	}

	// store the result values.
	atomic_store_explicit(&_->____rv, ___, memory_order_release);
	atomic_store_explicit(&_->____rt, __, memory_order_release);

	// broadcast the result to all waiters.
	__cswiftslash_optr_t wptr;
	while (__cswiftslash_fifo_consume_nonblocking(_->____w, &wptr) == __CSWIFTSLASH_FIFO_CONSUME_RESULT) {
		// fire the result handler function any and all waiters.
		if (((__cswiftslash_future_wait_ptr_t)wptr)->____s == true) {
			// this is a synchronous waiter. we can unlock their mutex and move on.
			pthread_mutex_unlock(&((__cswiftslash_future_wait_ptr_t)wptr)->____m);
		} else {
			// fire the async handler. there is no mutex to handle in this scenario.
			((__cswiftslash_future_wait_ptr_t)wptr)->____e(__, ___, ((__cswiftslash_future_wait_ptr_t)wptr)->____c);
			// free the heap pointer from memory
			____cswiftslash_future_wait_t_destroy_async((__cswiftslash_future_wait_ptr_t)wptr);
		}
	}

	returnSuccess:
		// return true, since we successfully broadcasted the result.
		pthread_mutex_unlock(&_->____m);
		return true;

	returnFailure:
		// return false, since we failed to broadcast the result.
		pthread_mutex_unlock(&_->____m);
		return false;
}