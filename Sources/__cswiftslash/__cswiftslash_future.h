// LICENSE MIT
// copyright (c) tanner silva 2024. all rights reserved.
#ifndef CLIBSWIFTSLASH_PTRFUTURE_H
#define CLIBSWIFTSLASH_PTRFUTURE_H

#include "__cswiftslash_fifo.h"
#include "__cswiftslash_types.h"
#include "__cswiftslash_future.h"

#include <pthread.h>

// handler types -----

/// @brief a future result handler.
/// @param res_typ the result type value.
/// @param res_ptr the result pointer (optional).
/// @param ctx_ptr the context pointer (optional).
typedef void(^ future_result_val_handler_f)(
	const uint8_t res_typ,
	const _cswiftslash_optr_t res_ptr,
	const _cswiftslash_optr_t ctx_ptr
);

/// @brief a future error handler.
/// @param err_typ the error type value.
/// @param err_ptr the error pointer (optional).
/// @param ctx_ptr the context pointer (optional).
typedef void(^ future_result_err_handler_f)(
	const uint8_t err_type,
	const _cswiftslash_optr_t err_ptr,
	const _cswiftslash_optr_t ctx_ptr
);

/// @brief a future cancel handler.
/// @param ctx_ptr the context pointer (optional).
typedef void(^ future_result_cancel_handler_f)(
	const _cswiftslash_optr_t ctx_ptr
);

/// @brief a future that will either succeed with a pointer type and pointer, or fail with an error type and pointer.
typedef struct _cswiftslash_future {
	// internal state mechanisms for the future itself.
	_Atomic uint8_t statVal;		// internal status value.
	pthread_mutex_t mutex;			// internal mutex for the condition.
	
	// user fields related to the result.
	_Atomic uint8_t fres_val_type;					// result value type (user field).
	_Atomic _cswiftslash_optr_t fres_val;			// result value (user field).

	// this is where waiters for the future are stored. items within this fifo are handled differently depending on their synchronous or asynchronous nature.
	_cswiftslash_fifo_linkpair_t waiters;
} _cswiftslash_future_t;

/// @brief a pointer to a future.
typedef _cswiftslash_future_t*_Nonnull _cswiftslash_future_ptr_t;

// init and deinit -----

/// @brief initialize a future.
/// @return the initialized future stackspace
_cswiftslash_future_t _cswiftslash_future_t_init(void);

/// @brief destroy a future. behavior is undefined if this is called while the future is still in use.
/// @param future the future to deallocate.
/// @param ctx_ptr the context pointer to pass to the result handler.
/// @param res_handler the result handler to call when the future is complete.
/// @param err_handler the error handler to call when the future is complete.
/// @return 0 if the future was destroyed, -1 if the future was not destroyed.
int _cswiftslash_future_t_destroy(
	_cswiftslash_future_t future,
	_cswiftslash_optr_t ctx_ptr,
	const _Nonnull future_result_val_handler_f res_handler,
	const _Nonnull future_result_err_handler_f err_handlerf
);

// waiting for the result -----

/// @brief block the calling thread until the future is complete.
/// @param future the future to wait for.
/// @param ctx_ptr the context pointer to pass to the result handler.
/// @param res_handler the result handler to call when the future is complete.
/// @param err_handler the error handler to call when the future is complete.
/// @param cancel_handler the cancel handler to call when the future is cancelled.
/// @return void is returned (calling thread is no longer blocked) when one of the result handlers is fired with the result.
void _cswiftslash_future_t_wait_sync(
	const _cswiftslash_future_ptr_t future,
	const _cswiftslash_optr_t ctx_ptr,
	const _Nonnull future_result_val_handler_f res_handler,
	const _Nonnull future_result_err_handler_f err_handler,
	const _Nonnull future_result_cancel_handler_f cancel_handler
);

/// @brief register completion handlers for the future and return immediately. handler functions will be called from the thread that completes the future.
/// @param future the future to wait for.
/// @param ctx_ptr the context pointer to pass to the result handler.
/// @param res_handler the result handler to call (from another thread) when the future is complete.
/// @param err_handler the error handler to call (from another thread) when the future is complete.
/// @param cancel_handler the cancel handler to call (from another thread) when the future is cancelled.
/// @return void is returned after the handlers are registered.
void _cswiftslash_future_t_wait_async(
	const _cswiftslash_future_ptr_t future,
	const _cswiftslash_optr_t ctx_ptr,
	const _Nonnull future_result_val_handler_f res_handler,
	const _Nonnull future_result_err_handler_f err_handler,
	const _Nonnull future_result_cancel_handler_f cancel_handler
);

// delivering the result -----

/// broadcast a completion result to all threads waiting on the future.
/// @param future the future to broadcast to.
/// @param res_type the result type - an 8 bit value.
/// @param res_val the result value - an optional pointer.
/// @return whether the broadcast was successful.
bool _cswiftslash_future_t_broadcast_res_val(
	const _cswiftslash_future_ptr_t future,
	const uint8_t res_type,
	const _cswiftslash_optr_t res_val
);

/// broadcast a completion result to all threads waiting on the future.
/// @param future the future to broadcast to.
/// @param res_type the result type - an 8 bit value.
/// @param res_val the result value - an optional pointer.
/// @return whether the broadcast was successful.
bool _cswiftslash_future_t_broadcast_res_throw(
	const _cswiftslash_future_ptr_t future,
	const uint8_t res_type,
	const _cswiftslash_optr_t res_val
);

/// @brief broadcast a cancellation to all threads waiting on the future.
/// @param future the future to broadcast to.
/// @return whether the broadcast was successful.
bool _cswiftslash_future_t_broadcast_cancel(
	const _cswiftslash_future_ptr_t future
);

#endif // CLIBSWIFTSLASH_PTRFUTURE_H