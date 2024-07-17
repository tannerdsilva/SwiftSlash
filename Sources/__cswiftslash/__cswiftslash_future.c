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
typedef struct _cswiftslash_future_syncwait_t {
	_cswiftslash_optr_t ctx_ptr;

	const bool is_sync;
	pthread_mutex_t sync_wait;

	const _Nullable future_result_val_handler_f res_handler;
	const _Nullable future_result_err_handler_f err_handler;
	const _Nullable future_result_cancel_handler_f cancel_handler;
	
} _cswiftslash_future_syncwait_t;

_cswiftslash_future_t _cswiftslash_future_t_init(void) {
	_cswiftslash_future_t newfuture;

	// initialize the status related variables
    atomic_store_explicit(&newfuture.statVal, FUTURE_STATUS_PEND, memory_order_release);
	pthread_mutex_init(&newfuture.mutex, NULL);

	// initialize the result related variables
	newfuture.waiters = _cswiftslash_fifo_init(NULL);

	// return the stack space
	return newfuture;
}

int _cswiftslash_future_t_destroy(
	_cswiftslash_future_t future,
	void *_Nullable ctx_ptr,
	const _Nonnull future_result_val_handler_f res_handler,
	const _Nonnull future_result_err_handler_f err_handler
) {

	// destroy the condition related to this future
	pthread_mutex_destroy(&future.mutex);

	_cswiftslash_fifo_close(&future.waiters, ^(void *_Nonnull ptr) {
		free(ptr);
	});

	// load the state of the future
	int8_t curstat = atomic_load_explicit(&future.statVal, memory_order_acquire);
	switch (curstat) {
		case FUTURE_STATUS_PEND:
			return -1;

		case FUTURE_STATUS_RESULT:
			// the future is fufilled with a result.
			
			// fire the result handler.
			res_handler(atomic_load_explicit(&future.fres_val_type, memory_order_acquire), atomic_load_explicit(&future.fres_val, memory_order_acquire), ctx_ptr);

			return 0;

		case FUTURE_STATUS_THROW:
			// the future is fufilled with an error.

			// fire the error handler.
			err_handler(atomic_load_explicit(&future.fres_val_type, memory_order_acquire), atomic_load_explicit(&future.fres_val, memory_order_acquire), ctx_ptr);

			return 0;

		case FUTURE_STATUS_CANCEL:
			return 0;
		default:
			return -1;
	}
}

void _cswiftslash_future_t_wait_sync(
	const _cswiftslash_future_ptr_t future,
	const _cswiftslash_optr_t ctx_ptr,
	const _Nonnull future_result_val_handler_f res_handler,
	const _Nonnull future_result_err_handler_f err_handler,
	const _Nonnull future_result_cancel_handler_f cancel_handler
) {

	// configure the waiter information for this function call. none of the fields are used except for the is_sync bool and its sync_wait mutex, since everything is handled synchronously in this function.
	_cswiftslash_future_syncwait_t waitersStack = {
		.ctx_ptr = NULL,
		.is_sync = true,
		.res_handler = NULL,
		.err_handler = NULL,
		.cancel_handler = NULL,
	};
	pthread_mutex_init(&waitersStack.sync_wait, NULL);		// initialize the mutex for the sync_wait stack.
	pthread_mutex_lock(&waitersStack.sync_wait);			// claim this lock in anticipation of passing it into the waiters fifo.

	// lock the future mutex so that the structure can be kept in a consistent state.
	pthread_mutex_lock(&future->mutex);

	#ifdef DEBUG
	// this is a theoretical possibility for this function to infinite loop (although this should be impossible in practice, unless there is a bug). this code takes the extra compute headroom of the debug build config to verify this is not the case.
	uint32_t loopCount = 0;
	#endif

	checkStat:	// goto checkStat requires the local and global locks to be held.

	// acquire the status of the future.
	switch (atomic_load_explicit(&future->statVal, memory_order_acquire)) {
		case FUTURE_STATUS_PEND:
			// the future is pending a result.

			// broadcast our thread as a waiter.
			if (_cswiftslash_fifo_pass(&future->waiters, (void*)&waitersStack) != 0) {
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
		pthread_mutex_unlock(&waitersStack.sync_wait);
		// destroy the local lock.
		pthread_mutex_destroy(&waitersStack.sync_wait);

		return; // cleanup complete, return to the caller.

	blockUntilDone:	// goto blockUntilDone requires the local and global locks to be held.

		#ifdef DEBUG
		// document that we have looped one time.
		loopCount += 1;
		#endif

		// remove the lock which keeps us synchronized with the global memory of the future.
		pthread_mutex_unlock(&future->mutex);
		// wait for the result to be broadcasted.
		pthread_mutex_lock(&waitersStack.sync_wait);
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
	// build the memory that defines how we want to wait for the future. this might not be used if the future is already complete.
	const _cswiftslash_future_syncwait_t waitersStack = {
		.ctx_ptr = ctx_ptr,
		.is_sync = false,
		.res_handler = res_handler,
		.err_handler = err_handler,
		.cancel_handler = cancel_handler,
	};
	// this is an async call so the waiter information must be heap allocated.
	const _cswiftslash_future_syncwait_t* waiters = (const _cswiftslash_future_syncwait_t*)memcpy(malloc(sizeof(_cswiftslash_future_syncwait_t)), &waitersStack, sizeof(_cswiftslash_future_syncwait_t));

	// acquire the global lock for this instance.
	pthread_mutex_lock(&future->mutex);

	// load the state of the future.
	int8_t curstat = atomic_load_explicit(&future->statVal, memory_order_acquire);

	checkStat:
	switch (curstat) {
		case FUTURE_STATUS_PEND:

			// broadcast our thread as a waiter.
			if (_cswiftslash_fifo_pass(&future->waiters, (void*)&waitersStack) != 0) {
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
		free((void*)waiters);
		pthread_mutex_unlock(&future->mutex);
		return;

	returnTimeWaiting:
		// the future is not yet complete, so we must not free the newly allocated memory.
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
	while (_cswiftslash_fifo_consume_nonblocking(&future->waiters, (void*)&wptr) == 0) {
		// fire the result handler function any and all waiters.
		if (((_cswiftslash_future_syncwait_t*)wptr)->is_sync == true) {
			// this is a synchronous waiter. we can unlock their mutex and move on.
			pthread_mutex_unlock(&((_cswiftslash_future_syncwait_t*)wptr)->sync_wait);
		} else {
			// fire the async handler. there is no mutex to handle in this scenario.
			((_cswiftslash_future_syncwait_t*)wptr)->res_handler(res_type, res_val, ((_cswiftslash_future_syncwait_t*)wptr)->ctx_ptr);
			// free the heap pointer from memory
			free((void*)wptr);
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
		if (((_cswiftslash_future_syncwait_t*)wptr)->is_sync == true) {
			// this is a synchronous waiter. we can unlock their mutex and move on.
			pthread_mutex_unlock(&((_cswiftslash_future_syncwait_t*)wptr)->sync_wait);
		} else {
			// fire the async handler. there is no mutex to handle in this scenario.
			((_cswiftslash_future_syncwait_t*)wptr)->err_handler(res_type, res_val, ((_cswiftslash_future_syncwait_t*)wptr)->ctx_ptr);
			// free the heap pointer from memory
			free((void*)wptr);
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


bool _cswiftslash_future_t_broadcast_cancel(const _cswiftslash_future_ptr_t future) {
	// acquire the global lock for synchronization.
	pthread_mutex_lock(&future->mutex);
	
	// flip the status from pending to successfully fufilled.
	uint8_t expected_complete = FUTURE_STATUS_PEND;
	if (atomic_compare_exchange_strong_explicit(&future->statVal, &expected_complete, FUTURE_STATUS_CANCEL, memory_order_acq_rel, memory_order_acquire) == false) {
		// the item was not the expected value and therefore NOT assigned.
		// this means that someone else is working to close the structure, so we should return failure and do nothing (dont want to double close).
		goto returnFailure;
	}

	// other threads may have been waiting on this result. notify the waiters.
	_cswiftslash_optr_t wptr;
	while (_cswiftslash_fifo_consume_nonblocking(&future->waiters, &wptr) == 0) {
		// fire the result handler function any and all waiters.
		if (((_cswiftslash_future_syncwait_t*)wptr)->is_sync == true) {
			// this is a synchronous waiter. we can unlock their mutex and move on.
			pthread_mutex_unlock(&((_cswiftslash_future_syncwait_t*)wptr)->sync_wait);
		} else {
			// fire the async handler. there is no mutex to handle in this scenario.
			((_cswiftslash_future_syncwait_t*)wptr)->cancel_handler(((_cswiftslash_future_syncwait_t*)wptr)->ctx_ptr);
			// free the heap pointer from memory
			free((void*)wptr);
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