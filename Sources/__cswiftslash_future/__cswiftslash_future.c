// LICENSE MIT
// copyright (c) tanner silva 2024. all rights reserved.
#include "__cswiftslash_future.h"

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


/// @brief used to represent a thread that is synchronously waiting and blocking for the result of a future.
typedef struct _cswiftslash_future_wait_t {
	/// @brief the context pointer that will be transparenly passed to the result handler.
	_cswiftslash_optr_t ctx_ptr;

	/// @brief if the waiter is synchronous, this will be true.
	const bool is_sync;
	/// @brief the mutex that is used to block the thread until the future is complete. this is only used if the waiter is synchronous.
	pthread_mutex_t sync_wait;

	/// @brief the result handler to call when the future is complete.
	future_result_val_handler_f res_handler_ptr;
	/// @brief the error handler to call when the future is complete.
	future_result_err_handler_f err_handler_ptr;
	/// @brief the cancel handler to call when the future is cancelled and a result will never be available.
	future_result_cancel_handler_f cancel_handler_ptr;
	
} _cswiftslash_future_wait_t;

/// @brief a pointer to a future waiter.
typedef _cswiftslash_future_wait_t *_Nonnull _cswiftslash_future_wait_ptr_t;

/// @brief create a new synchronous waiter for a future.
/// @param ctx_ptr the context pointer to pass to the result handler when it comes time to fire.
/// @param res_handler the handler to call when the future is complete with a valid result.
/// @param err_handler the handler to call when the future is complete with an error.
/// @param cancel_handler the handler to call when the future is cancelled and a result will never be available.
/// @return a pointer to the waiter structure on the heap.
_cswiftslash_future_wait_ptr_t ____cswiftslash_future_wait_t_init_sync(_cswiftslash_optr_t ctx_ptr, future_result_val_handler_f res_handler, future_result_err_handler_f err_handler, future_result_cancel_handler_f cancel_handler) {
	// declare the new structure value on the stack.
	_cswiftslash_future_wait_t newwaiter = {
		.ctx_ptr = ctx_ptr,
		.is_sync = true,
		.res_handler_ptr = res_handler,
		.err_handler_ptr = err_handler,
		.cancel_handler_ptr = cancel_handler
	};

	// initialize a new mutex onto the stack space.
	if (pthread_mutex_init(&newwaiter.sync_wait, NULL) != 0) {
		// fatal error. this would be a bug.
		printf("swiftslash future internal error: couldn't initialize future sync_wait mutex\n");
		abort();
	}

	// copy the waiter to the heap.
	_cswiftslash_future_wait_ptr_t heapwaiter = malloc(sizeof(_cswiftslash_future_wait_t));
	memcpy(heapwaiter, &newwaiter, sizeof(_cswiftslash_future_wait_t));

	return heapwaiter;
}

/// @brief create a new asynchronous waiter for a future.
/// @param ctx_ptr the context pointer to pass to the result handler when it comes time to fire.
/// @param res_handler the handler to call when the future is complete with a valid result.
/// @param err_handler the handler to call when the future is complete with an error.
/// @param cancel_handler the handler to call when the future is cancelled and a result will never be available.
/// @return the waiter structure.
_cswiftslash_future_wait_ptr_t ____cswiftslash_future_wait_t_init_async(_cswiftslash_optr_t ctx_ptr, future_result_val_handler_f res_handler, future_result_err_handler_f err_handler, future_result_cancel_handler_f cancel_handler) {
	// create a new waiter structure in the stack.
	_cswiftslash_future_wait_t newwaiter = {
		.ctx_ptr = ctx_ptr,
		.is_sync = false,
		.res_handler_ptr = (_cswiftslash_ptr_t)res_handler,
		.err_handler_ptr = (_cswiftslash_ptr_t)err_handler,
		.cancel_handler_ptr = (_cswiftslash_ptr_t)cancel_handler
	};

	// no mutex to initialize for async waiters.

	// copy the waiter to the heap.
	_cswiftslash_future_wait_ptr_t heapwaiter = malloc(sizeof(_cswiftslash_future_wait_t));
	memcpy(heapwaiter, &newwaiter, sizeof(_cswiftslash_future_wait_t));

	// return the heap waiter.
	return heapwaiter;
}

void ____cswiftslash_future_wait_t_destroy_sync(_cswiftslash_future_wait_ptr_t waiter) {
	// destroy the mutex for the sync_wait stack.
	pthread_mutex_destroy(&waiter->sync_wait);

	// free the memory from the heap.
	free((void*)waiter);
}

void ____cswiftslash_future_wait_t_destroy_async(_cswiftslash_future_wait_ptr_t waiter) {
	// free the heap pointer from memory
	free((void*)waiter);
}

bool ____cswiftslash_future_t_broadcast_cancel(const _cswiftslash_future_ptr_t future) {	
	// flip the status from pending to successfully fufilled.
	uint8_t expected_complete = FUTURE_STATUS_PEND;
	if (atomic_compare_exchange_strong_explicit(&future->statVal, &expected_complete, FUTURE_STATUS_CANCEL, memory_order_acq_rel, memory_order_acquire) == false) {
		// the item was not the expected value and therefore NOT assigned.
		// this means that someone else is working to close the structure, so we should return failure and do nothing (dont want to double close).
		return false;
	}

	// other threads may have been waiting on this result. notify the waiters.
	_cswiftslash_optr_t wptr; // each waiter is stored here as the fifo pipeline is consumed.
	while (_cswiftslash_fifo_consume_nonblocking(&future->waiters, &wptr) == 0) {
		// fire the result handler function any and all waiters.
		if (((_cswiftslash_future_wait_ptr_t)wptr)->is_sync == true) {
			// this is a synchronous waiter. we can unlock their mutex and move on.
			pthread_mutex_unlock(&((_cswiftslash_future_wait_ptr_t)wptr)->sync_wait);
		} else {
			((_cswiftslash_future_wait_ptr_t)wptr)->cancel_handler_ptr(((_cswiftslash_future_wait_ptr_t)wptr)->ctx_ptr);
			// free the heap pointer from memory
			_cswiftslash_future_wait_destroy_async((_cswiftslash_future_wait_ptr_t)wptr);
		}
	}

	return true;
}

/// @brief this is an internal function used to close the future waiters fifo.
/// @param ptr the pointer to a waiter info structure that should be freed.
void ____cswiftslash_future_fifo_close(void *_Nonnull ptr) {
	printf("swiftslash future internal error: future waiter fifo was closed while containing waiters. this should be mechanically impossible - this is a bug\n");
	abort();
}

_cswiftslash_future_ptr_t _cswiftslash_future_t_init(void) {
	_cswiftslash_future_ptr_t fptr = malloc(sizeof(_cswiftslash_future_t));

	atomic_store_explicit(&fptr->statVal, FUTURE_STATUS_PEND, memory_order_release);
	if (pthread_mutex_init(&fptr->mutex, NULL) != 0) {
		// fatal error. this would be a bug.
		printf("swiftslash future internal error: couldn't initialize future mutex\n");
		abort();
	}

	fptr->waiters = _cswiftslash_fifo_init(NULL);

	// return the stack space
	return fptr;
}

void _cswiftslash_future_t_destroy(
	_cswiftslash_future_ptr_t future,
	const _cswiftslash_optr_t ctx_ptr,
	const _Nonnull future_result_val_handler_f res_handler,
	const _Nonnull future_result_err_handler_f err_handler
) {
	// lock the internal state of the future to set the state to cancelled (if it needs to be).
	pthread_mutex_lock(&future->mutex);
	int8_t curstat = atomic_load_explicit(&future->statVal, memory_order_acquire);
	switch (curstat) {
		case FUTURE_STATUS_PEND:
			if (____cswiftslash_future_t_broadcast_cancel(future) == false) {
				printf("swiftslash future internal error: couldn't cancel future\n");
				abort();
			}
			break;

		case FUTURE_STATUS_RESULT:
			res_handler(atomic_load_explicit(&future->fres_val_type, memory_order_acquire), atomic_load_explicit(&future->fres_val, memory_order_acquire), ctx_ptr);
			break;

		case FUTURE_STATUS_THROW:
			err_handler(atomic_load_explicit(&future->fres_val_type, memory_order_acquire), atomic_load_explicit(&future->fres_val, memory_order_acquire), ctx_ptr);
			break;

		default:
			printf("swiftslash future internal error: invalid future status\n");
			abort();
	}
	pthread_mutex_unlock(&future->mutex);

	// destroy the fifo of waiters.
	pthread_mutex_lock(&future->mutex);
	_cswiftslash_fifo_close(&future->waiters, ____cswiftslash_future_fifo_close);
	pthread_mutex_unlock(&future->mutex);

	// destroy the memory.
	pthread_mutex_destroy(&future->mutex);
	free(future);
}

void _cswiftslash_future_t_wait_sync(
	const _cswiftslash_future_ptr_t future,
	const _cswiftslash_optr_t ctx_ptr,
	const _Nonnull future_result_val_handler_f res_handler,
	const _Nonnull future_result_err_handler_f err_handler,
	const _Nonnull future_result_cancel_handler_f cancel_handler
) {

	// lock the future mutex so that the structure can be kept in a consistent state.
	pthread_mutex_lock(&future->mutex);

	#ifdef DEBUG
	// this is a theoretical possibility for this function to infinite loop (although this should be impossible in practice, unless there is a bug). this code takes the extra compute headroom of the debug build config to verify this is not the case.
	uint32_t loopCount = 0;
	#endif

	_cswiftslash_future_wait_ptr_t waitHeap = _cswiftslash_future_wait_init_sync(ctx_ptr, res_handler, err_handler, cancel_handler);
	pthread_mutex_lock(&waitHeap->sync_wait);

	checkStat:	// goto checkStat requires the local and global locks to be held.

	// acquire the status of the future.
	switch (atomic_load_explicit(&future->statVal, memory_order_acquire)) {
		case FUTURE_STATUS_PEND:

			// broadcast our thread as a waiter.
			if (_cswiftslash_fifo_pass(&future->waiters, (_cswiftslash_ptr_t)waitHeap) != 0) {

				// internal fatal error. this would be a bug
				printf("swiftslash future internal error: couldn't insert waiter into the queue\n");
				abort();
			}

			#ifdef DEBUG
			if (loopCount >= CLIBSWIFTSLASH_PTRFUTURE_MAXLOOPS_SYNC) {
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
			res_handler(atomic_load_explicit(&future->fres_val_type, memory_order_acquire), atomic_load_explicit(&future->fres_val, memory_order_acquire), ctx_ptr);

			goto returnTime;

		case FUTURE_STATUS_THROW:
			// the future is fufilled with an error.

			// fire the error handler.
			err_handler(atomic_load_explicit(&future->fres_val_type, memory_order_acquire), atomic_load_explicit(&future->fres_val, memory_order_acquire), ctx_ptr);

			goto returnTime;

		case FUTURE_STATUS_CANCEL:
			// the future was cancelled. fire the handler and exit.
			cancel_handler(ctx_ptr);
			
			goto returnTime;
		
		default:
			printf("swiftslash future internal error: invalid future status\n");
			abort();
	}

	returnTime:	// goto returnTime requires the local and global locks to be held.

		// no longer need to be synchronized with the global memory, lets free that first.
		pthread_mutex_unlock(&future->mutex);
		// unlock the local lock.
		pthread_mutex_unlock(&waitHeap->sync_wait);
		// destroy the local waiter.
		_cswiftslash_future_wait_destroy_sync(waitHeap);

		return; // cleanup complete, return to the caller.

	blockUntilDone:	// goto blockUntilDone requires the local and global locks to be held.

		#ifdef DEBUG
		// document that we have looped one time.
		loopCount += 1;
		#endif

		// remove the lock which keeps us synchronized with the global memory of the future.
		pthread_mutex_unlock(&future->mutex);
		// wait for the result to be broadcasted.
		pthread_mutex_lock(&waitHeap->sync_wait);
		// relock the global memory of the future.
		pthread_mutex_lock(&future->mutex);
		
		goto checkStat;	// recheck the status of the future with both locks acquired.
}

void _cswiftslash_future_t_wait_async(
	const _cswiftslash_future_ptr_t future,
	const _cswiftslash_optr_t ctx_ptr,
	const _Nonnull future_result_val_handler_f res_handler,
	const _Nonnull future_result_err_handler_f err_handler,
	const _Nonnull future_result_cancel_handler_f cancel_handler
) {
	// create a new waiter for this future.
	_cswiftslash_future_wait_ptr_t waiterHeap = _cswiftslash_future_wait_init_async(ctx_ptr, res_handler, err_handler, cancel_handler);

	// acquire the global lock for this instance.
	pthread_mutex_lock(&future->mutex);

	// load the state of the future.
	int8_t curstat = atomic_load_explicit(&future->statVal, memory_order_acquire);

	checkStat:
	switch (curstat) {
		case FUTURE_STATUS_PEND:

			// broadcast our thread as a waiter.
			if (_cswiftslash_fifo_pass(&future->waiters, (_cswiftslash_ptr_t)waiterHeap) != 0) {
				// internal fatal error. this would be a bug
				printf("swiftslash future internal error: couldn't insert waiter into the queue\n");
				abort();
			}

			goto returnTimeWaiting;

		case FUTURE_STATUS_RESULT:
			// the future is fufilled with a result.
			
			// fire the result handler.
			res_handler(atomic_load_explicit(&future->fres_val_type, memory_order_acquire), atomic_load_explicit(&future->fres_val, memory_order_acquire), ctx_ptr);

			goto returnTimeNoWait;

		case FUTURE_STATUS_THROW:
			// the future is fufilled with an error.

			// fire the error handler.
			err_handler(atomic_load_explicit(&future->fres_val_type, memory_order_acquire), atomic_load_explicit(&future->fres_val, memory_order_acquire), ctx_ptr);

			goto returnTimeNoWait;

		case FUTURE_STATUS_CANCEL:
			// the future was cancelled. fire the handler and exit.
			
			// fire the cancel handler.
			cancel_handler(NULL);
			
			goto returnTimeNoWait;
		
		default:
			printf("swiftslash future internal error: invalid future status\n");
			abort();
	}

	returnTimeNoWait:
		// a result was immediately available, so we can free the memory and return.

		// unlock the global lock.
		pthread_mutex_unlock(&future->mutex);

		// free the local waiter.
		_cswiftslash_future_wait_destroy_async(waiterHeap);
		return;

	returnTimeWaiting:
		// the future is not yet complete, so we must not free the newly allocated memory.

		// unlock the global lock.
		pthread_mutex_unlock(&future->mutex);
		return;
}

bool _cswiftslash_future_t_broadcast_res_val(const _cswiftslash_future_ptr_t future, const uint8_t res_type, const _cswiftslash_optr_t res_val) {
	// acquire the global lock for synchronization.
	pthread_mutex_lock(&future->mutex);

	// flip the status from pending to successfully fufilled.
    uint8_t expected_complete = FUTURE_STATUS_PEND;
	if (atomic_compare_exchange_strong_explicit(&future->statVal, &expected_complete, FUTURE_STATUS_RESULT, memory_order_acq_rel, memory_order_acquire) == false) {
		// the item was not the expected value and therefore NOT assigned.
		// this means that someone else is working to close the structure, so we should return failure and do nothing (dont want to double close).
		goto returnFailure;
	}

	// store the result values.
	atomic_store_explicit(&future->fres_val, res_val, memory_order_release);
	atomic_store_explicit(&future->fres_val_type, res_type, memory_order_release);

	// broadcast the result to all waiters.
	_cswiftslash_optr_t wptr;
	while (_cswiftslash_fifo_consume_nonblocking(&future->waiters, &wptr) == 0) {
		// fire the result handler function any and all waiters.
		if (((_cswiftslash_future_wait_ptr_t)wptr)->is_sync == true) {
			// this is a synchronous waiter. we can unlock their mutex and move on.
			pthread_mutex_unlock(&((_cswiftslash_future_wait_ptr_t)wptr)->sync_wait);
		} else {
			// fire the async handler. there is no mutex to handle in this scenario.
			((_cswiftslash_future_wait_ptr_t)wptr)->res_handler_ptr(res_type, res_val, ((_cswiftslash_future_wait_ptr_t)wptr)->ctx_ptr);
			// free the heap pointer from memory
			_cswiftslash_future_wait_destroy_async((_cswiftslash_future_wait_ptr_t)wptr);
		}
	}

	goto returnSuccess;

	returnSuccess:
		// return true, since we successfully broadcasted the result.
		pthread_mutex_unlock(&future->mutex);
		return true;

	returnFailure:
		// return false, since we failed to broadcast the result.
		pthread_mutex_unlock(&future->mutex);
		return false;
}

bool _cswiftslash_future_t_broadcast_res_throw(const _cswiftslash_future_ptr_t future, const uint8_t res_type, const _cswiftslash_optr_t res_val) {
	// acquire the global lock for synchronization.
	pthread_mutex_lock(&future->mutex);
	
	// flip the status from pending to successfully fufilled.
	uint8_t expected_complete = FUTURE_STATUS_PEND;
	if (atomic_compare_exchange_strong_explicit(&future->statVal, &expected_complete, FUTURE_STATUS_THROW, memory_order_acq_rel, memory_order_acquire) == false) {
		// the item was not the expected value and therefore NOT assigned.
		// this means that someone else is working to close the structure, so we should return failure and do nothing (dont want to double close).
		goto returnFailure;
	}

	// store the result values.
	atomic_store_explicit(&future->fres_val, res_val, memory_order_release);
	atomic_store_explicit(&future->fres_val_type, res_type, memory_order_release);

	// broadcast the result to all waiters.
	_cswiftslash_optr_t wptr;
	while (_cswiftslash_fifo_consume_nonblocking(&future->waiters, &wptr) == 0) {
		// fire the result handler function any and all waiters.
		if (((_cswiftslash_future_wait_ptr_t)wptr)->is_sync == true) {
			// this is a synchronous waiter. we can unlock their mutex and move on.
			pthread_mutex_unlock(&((_cswiftslash_future_wait_ptr_t)wptr)->sync_wait);
		} else {
			// fire the async handler. there is no mutex to handle in this scenario.
			((_cswiftslash_future_wait_ptr_t)wptr)->err_handler_ptr(res_type, res_val, ((_cswiftslash_future_wait_ptr_t)wptr)->ctx_ptr);
			// free the heap pointer from memory
			_cswiftslash_future_wait_destroy_async((_cswiftslash_future_wait_ptr_t)wptr);
		}
	}

	goto returnSuccess;

	returnSuccess:
		// return true, since we successfully broadcasted the result.
		pthread_mutex_unlock(&future->mutex);
		return true;

	returnFailure:
		// return false, since we failed to broadcast the result.
		pthread_mutex_unlock(&future->mutex);
		return false;
}