#ifndef CLIBSWIFTSLASH_FUTURE_INT_H
#define CLIBSWIFTSLASH_FUTURE_INT_H

#include "types.h"

#include <pthread.h>

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
} future_status_t;


// handler types -----

/// @brief a future result handler.
/// @param res_type the result type - an 8 bit value.
/// @param res_val the result value - a 64 bit value.
typedef void(^_Nonnull future_result_val_handler_f)(const uint8_t, const int64_t);

/// @brief a future error handler.
/// @param res_type the error type - an 8 bit value.
/// @param res_val the error value - a 64 bit value.
typedef void(^_Nonnull future_result_err_handler_f)(const uint8_t, const int64_t);

/// @brief a future cancel handler.
typedef void(^_Nonnull future_result_cancel_handler_f)(void);


/// @brief a future that will produce a 64 bit integer. 
typedef struct future_int64 {
	// outcome of the future.
	_Atomic uint8_t statVal;		// internal status value.
	pthread_cond_t statCond;		// internal condition for when the status changes.
	
	// user fields related to the result.
	_Atomic uint8_t fres_val_type;		// result value type (user field).
	_Atomic int64_t fres_val;			// result value (user field).
} future_int64_t;

typedef future_int64_t*_Nonnull future_int64_ptr_t;


// init and deinit -----

/// @brief initialize an int future.
/// @return the initialized future stackspace, which will have a reference count of 1.
future_int64_t future_int64_t_init(void);

/// @brief destroy a future. behavior is undefined if this is called while the future is still in use.
/// @param future the future to deallocate.
void future_int64_t_destroy(future_int64_ptr_t future);


// waiting for the result -----

/// @brief block the calling thread until the future is complete.
/// @param future the future to wait for.
/// @param mutex the mutex to use to sync and manage state
/// @param res_handler the result handler to call when the future is complete.
/// @param err_handler the error handler to call when the future is complete.
/// @param cancel_handler the cancel handler to call when the future is cancelled.
/// @return the result of the future.
void future_int64_t_wait_sync(const future_int64_ptr_t future, pthread_mutex_t*_Nonnull mutex, const future_result_val_handler_f res_handler, const future_result_err_handler_f err_handler, const future_result_cancel_handler_f cancel_handler);


// delivering the result -----

/// broadcast a completion result to all threads waiting on the future.
/// @param future the future to broadcast to.
/// @param res_type the result type - an 8 bit value.
/// @param res_val the result value - a 64 bit value.
/// @return whether the broadcast was successful.
bool future_int64_t_broadcast_res_val(const future_int64_ptr_t future, const uint8_t res_type, const int64_t res_val);

/// broadcast a completion result to all threads waiting on the future.
/// @param future the future to broadcast to.
/// @param res_type the result type - an 8 bit value.
/// @param res_val the result value - a 64 bit value.
/// @return whether the broadcast was successful.
bool future_int64_t_broadcast_err_val(const future_int64_ptr_t future, const uint8_t res_type, const int64_t res_val);

/// @brief broadcast a cancellation to all threads waiting on the future.
/// @param future the future to broadcast to.
/// @return whether the broadcast was successful.
bool future_int64_t_broadcast_cancel(const future_int64_ptr_t future);

#endif // CLIBSWIFTSLASH_FUTURE_INT_H