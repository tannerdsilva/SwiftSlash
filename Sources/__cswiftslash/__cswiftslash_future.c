#include "__cswiftslash_future.h"

#include <stdatomic.h>

_cswiftslash_future_t _cswiftslash_future_t_init(void) {
    // the new int64 future to return
	_cswiftslash_future_t newfuture;

	// initialize the status related variables
    atomic_store_explicit(&newfuture.statVal, FUTURE_STATUS_PEND, memory_order_release);
    pthread_cond_init(&newfuture.statCond, NULL);
	pthread_mutex_init(&newfuture.mutex, NULL);

	// return the stack space
	return newfuture;
}

int _cswiftslash_future_t_destroy(_cswiftslash_future_t future, const future_result_val_handler_f res_handler, const future_result_err_handler_f err_handler) {
	// load the state of the future
	int8_t curstat = atomic_load_explicit(&future.statVal, memory_order_acquire);
	switch (curstat) {
		case FUTURE_STATUS_PEND:
			return -1;

		case FUTURE_STATUS_RESULT:
			// the future is fufilled with a result.
			
			// fire the result handler.
			res_handler(atomic_load_explicit(&future.fres_val, memory_order_acquire));

			return 0;

		case FUTURE_STATUS_THROW:
			// the future is fufilled with an error.

			// fire the error handler.
			err_handler(atomic_load_explicit(&future.fres_val, memory_order_acquire));

			return 0;

		case FUTURE_STATUS_CANCEL:
			return 0;
		default:
			return -1;
	}

	// destroy the condition related to this future
	pthread_cond_destroy(&future.statCond);
	pthread_mutex_destroy(&future.mutex);
}

void _cswiftslash_future_t_wait_sync(const _cswiftslash_future_ptr_t future, const future_result_val_handler_f res_handler, const future_result_err_handler_f err_handler, const future_result_cancel_handler_f cancel_handler) {
	// infinite loop will return when it is time to break;
	pthread_mutex_lock(&future->mutex);
	do {
		// load the state of the future
		int8_t curstat = atomic_load_explicit(&future->statVal, memory_order_acquire);
		switch (curstat) {
			case FUTURE_STATUS_PEND:
				// the future is not fufilled so we must wait for it
				pthread_cond_wait(&future->statCond, &future->mutex);
				
				// it is crucial to not return here because we dont know if the future is fufilled yet.
				break;

			case FUTURE_STATUS_RESULT:
				// the future is fufilled with a result.
				
				// fire the result handler.
				res_handler(atomic_load_explicit(&future->fres_val, memory_order_acquire));

				// exit the function.
				pthread_mutex_unlock(&future->mutex);
				return;

			case FUTURE_STATUS_THROW:
				// the future is fufilled with an error.

				// fire the error handler.
				err_handler(atomic_load_explicit(&future->fres_val, memory_order_acquire));

				// exit the function.
				pthread_mutex_unlock(&future->mutex);
				return;

			case FUTURE_STATUS_CANCEL:
				// the future was cancelled. fire the handler and exit.
				cancel_handler();
				pthread_mutex_unlock(&future->mutex);
				return;
			default:
				pthread_mutex_unlock(&future->mutex);
				return;
		}
	} while (true);
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
	
	// broadcast the condition to wake up all waiting threads.
	pthread_cond_broadcast(&future->statCond);

	// return true, since we successfully broadcasted the result.
	pthread_mutex_unlock(&future->mutex);
	return true;
}