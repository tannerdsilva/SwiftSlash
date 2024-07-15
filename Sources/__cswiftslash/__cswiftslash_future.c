#include "__cswiftslash_future.h"

#include <stdatomic.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

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
	void *_Nullable ctx_ptr;
	const future_result_val_handler_f res_handler;
	const future_result_err_handler_f err_handler;
	const future_result_cancel_handler_f cancel_handler;
	const bool is_sync;
	pthread_mutex_t *_Nullable sync_mutex;
} _cswiftslash_future_syncwait_t;


_cswiftslash_future_t _cswiftslash_future_t_init(void) {
	_cswiftslash_future_t newfuture;

	// initialize the status related variables
    atomic_store_explicit(&newfuture.statVal, FUTURE_STATUS_PEND, memory_order_release);
    pthread_cond_init(&newfuture.statCond, NULL);
	pthread_mutex_init(&newfuture.mutex, NULL);

	// initialize the result related variables
	newfuture.waiters = _cswiftslash_fifo_init();

	// return the stack space
	return newfuture;
}

int _cswiftslash_future_t_destroy(_cswiftslash_future_t future, void *_Nullable ctx_ptr, const future_result_val_handler_f res_handler, const future_result_err_handler_f err_handler) {

	// destroy the condition related to this future
	// pthread_cond_destroy(&future.statCond);
	pthread_mutex_destroy(&future.mutex);

	_cswiftslash_fifo_close(&future.waiters, ^(void *_Nonnull ptr) {
		_cswiftslash_future_syncwait_t *waiter = (_cswiftslash_future_syncwait_t*)ptr;
		if (waiter->is_sync == false) {
			free(waiter);
		}
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

void _cswiftslash_future_t_wait_result_infiniteloop(const _cswiftslash_future_ptr_t future, int8_t *_Nonnull stat) {
	while (*stat == FUTURE_STATUS_PEND) {
		pthread_cond_wait(&future->statCond, &future->mutex);
		*stat = atomic_load_explicit(&future->statVal, memory_order_acquire);
	}
}

void _cswiftslash_future_t_wait_sync(const _cswiftslash_future_ptr_t future, void *_Nullable ctx_ptr, const future_result_val_handler_f res_handler, const future_result_err_handler_f err_handler, const future_result_cancel_handler_f cancel_handler) {
	pthread_mutex_lock(&future->mutex);
	const _cswiftslash_future_syncwait_t waiters = {
		.ctx_ptr = ctx_ptr,
		.res_handler = res_handler,
		.err_handler = err_handler,
		.cancel_handler = cancel_handler,
		.is_sync = true
	};

	// load the state of the future
	int8_t curstat = atomic_load_explicit(&future->statVal, memory_order_acquire);

	checkStat:
	switch (curstat) {
		case FUTURE_STATUS_PEND:

			// the future is not fufilled so we must insert out waiters into the waiters queue.
			_cswiftslash_fifo_pass(&future->waiters, (void*)&waiters);

			// wait for the condition to be broadcasted.
			_cswiftslash_future_t_wait_result_infiniteloop(future, &curstat);

			// check the status again.
			goto checkStat;

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
			goto returnTime;
	}

	returnTime:
	pthread_mutex_unlock(&future->mutex);
	return;
}

void _cswiftslash_future_t_wait_async(const _cswiftslash_future_ptr_t future, const future_result_val_handler_f res_handler, const future_result_err_handler_f err_handler, const future_result_cancel_handler_f cancel_handler) {
	pthread_mutex_lock(&future->mutex);
	const _cswiftslash_future_syncwait_t waitersStack = {
		.ctx_ptr = NULL,
		.res_handler = res_handler,
		.err_handler = err_handler,
		.cancel_handler = cancel_handler,
		.is_sync = false
	};

	const _cswiftslash_future_syncwait_t* waiters = (const _cswiftslash_future_syncwait_t*)memcpy(malloc(sizeof(_cswiftslash_future_syncwait_t)), &waitersStack, sizeof(_cswiftslash_future_syncwait_t));

	// load the state of the future
	int8_t curstat = atomic_load_explicit(&future->statVal, memory_order_acquire);

	checkStat:
	switch (curstat) {
		case FUTURE_STATUS_PEND:

			// the future is not fufilled so we must insert out waiters into the waiters queue.
			if (_cswiftslash_fifo_pass(&future->waiters, (void*)&waiters) != 0) {
				// there was an error inserting the waiter into the queue.
				free((void*)waiters);
				goto returnTime;
			}

			goto returnTime;

		case FUTURE_STATUS_RESULT:
			// the future is fufilled with a result.
			
			// fire the result handler.
			res_handler(atomic_load_explicit(&future->fres_val_type, memory_order_acquire), atomic_load_explicit(&future->fres_val, memory_order_acquire), NULL);

			goto returnTime;

		case FUTURE_STATUS_THROW:
			// the future is fufilled with an error.

			// fire the error handler.
			err_handler(atomic_load_explicit(&future->fres_val_type, memory_order_acquire), atomic_load_explicit(&future->fres_val, memory_order_acquire), NULL);

			goto returnTime;

		case FUTURE_STATUS_CANCEL:
			// the future was cancelled. fire the handler and exit.
			cancel_handler(NULL);
			goto returnTime;
		
		default:
			goto returnTime;
	}

	returnTime:
	pthread_mutex_unlock(&future->mutex);
	return;
}

bool _cswiftslash_future_t_broadcast_res_val(const _cswiftslash_future_ptr_t future, const uint8_t res_type, const _cswiftslash_optr_t res_val) {
	pthread_mutex_lock(&future->mutex);

	// flip the status from pending to successfully fufilled.
    uint8_t expected_complete = FUTURE_STATUS_PEND;
	if (atomic_compare_exchange_strong_explicit(&future->statVal, &expected_complete, FUTURE_STATUS_RESULT, memory_order_acq_rel, memory_order_acquire) == false) {
		// the item was not the expected value and therefore NOT assigned.
		// this means that someone else is working to close the structure, so we should return failure and do nothing (dont want to double close).
		pthread_mutex_unlock(&future->mutex);
		return false; // failure
	}

	// store the result values.
	atomic_store_explicit(&future->fres_val, res_val, memory_order_release);
	atomic_store_explicit(&future->fres_val_type, res_type, memory_order_release);

	_cswiftslash_optr_t wptr;
	while (_cswiftslash_fifo_consume_nonblocking(&future->waiters, (void*)&wptr) == 0) {
		// fire the waiter handler.
		((_cswiftslash_future_syncwait_t*)wptr)->res_handler(res_type, res_val, ((_cswiftslash_future_syncwait_t*)wptr)->ctx_ptr);

		// free the heap memory if this is an async waiter.
		if (((_cswiftslash_future_syncwait_t*)wptr)->is_sync == false) {
			free(wptr);
		}
	}
	
	// broadcast the condition to wake up all waiting threads.
	pthread_cond_broadcast(&future->statCond);

	// return true, since we successfully broadcasted the result.
	pthread_mutex_unlock(&future->mutex);
    return true;
}

bool _cswiftslash_future_t_broadcast_res_throw(const _cswiftslash_future_ptr_t future, const uint8_t res_type, const _cswiftslash_optr_t res_val) {
	pthread_mutex_lock(&future->mutex);
	
	// flip the status from pending to successfully fufilled.
	uint8_t expected_complete = FUTURE_STATUS_PEND;
	if (atomic_compare_exchange_strong_explicit(&future->statVal, &expected_complete, FUTURE_STATUS_THROW, memory_order_acq_rel, memory_order_acquire) == false) {
		// the item was not the expected value and therefore NOT assigned.
		// this means that someone else is working to close the structure, so we should return failure and do nothing (dont want to double close).
		pthread_mutex_unlock(&future->mutex);
		return false; // failure
	}

	// store the result values.
	atomic_store_explicit(&future->fres_val, res_val, memory_order_release);
	atomic_store_explicit(&future->fres_val_type, res_type, memory_order_release);

	_cswiftslash_optr_t wptr;
	while (_cswiftslash_fifo_consume_nonblocking(&future->waiters, &wptr) == 0) {
		// fire the waiter handler.
		((_cswiftslash_future_syncwait_t*)wptr)->err_handler(res_type, res_val, ((_cswiftslash_future_syncwait_t*)wptr)->ctx_ptr);

		// free the heap memory if this is an async waiter.
		if (((_cswiftslash_future_syncwait_t*)wptr)->is_sync == false) {
			free(wptr);
		}
	}
	
	// broadcast the condition to wake up all waiting threads.
	pthread_cond_broadcast(&future->statCond);

	// return true, since we successfully broadcasted the result.
	pthread_mutex_unlock(&future->mutex);
	return true;
}


bool _cswiftslash_future_t_broadcast_cancel(const _cswiftslash_future_ptr_t future) {
	pthread_mutex_lock(&future->mutex);
	
	// flip the status from pending to successfully fufilled.
	uint8_t expected_complete = FUTURE_STATUS_PEND;
	if (atomic_compare_exchange_strong_explicit(&future->statVal, &expected_complete, FUTURE_STATUS_CANCEL, memory_order_acq_rel, memory_order_acquire) == false) {
		// the item was not the expected value and therefore NOT assigned.
		// this means that someone else is working to close the structure, so we should return failure and do nothing (dont want to double close).
		pthread_mutex_unlock(&future->mutex);
		return false; // failure
	}

	// other threads may have been waiting on this result. notify the waiters.
	_cswiftslash_optr_t wptr;
	while (_cswiftslash_fifo_consume_nonblocking(&future->waiters, &wptr) == 0) {
		((_cswiftslash_future_syncwait_t*)wptr)->cancel_handler(((_cswiftslash_future_syncwait_t*)wptr)->ctx_ptr);

		// free the heap memory if this is an async waiter.
		if (((_cswiftslash_future_syncwait_t*)wptr)->is_sync == false) {
			free(wptr);
		}
	}
	
	// broadcast the condition to wake up all waiting threads. this will prompt them to free the stack memory that was allocated for the waiters.
	pthread_cond_broadcast(&future->statCond); 

	// return true, since we successfully broadcasted the result.
	pthread_mutex_unlock(&future->mutex);
	return true;
}