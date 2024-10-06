/*
LICENSE MIT
copyright (c) tanner silva 2024. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

#ifndef __CLIBSWIFTSLASH_FUTURE_H
#define __CLIBSWIFTSLASH_FUTURE_H

#include "__cswiftslash_types.h"

#include <pthread.h>
#include <stdint.h>
#include <stdbool.h>

// handler types -----

// RESULT

// - FUNCTION
/// @brief a future result handler function.
/// @param res_typ the result type value.
/// @param res_ptr the result pointer (optional).
/// @param ctx_ptr the context pointer (optional).
typedef void(* __cswiftslash_future_result_val_handler_f)(
	const uint8_t res_typ,
	const __cswiftslash_optr_t res_ptr,
	const __cswiftslash_optr_t ctx_ptr
);

// ERROR
// - FUNCTION
/// @brief a future error handler function.
/// @param err_typ the error type value.
/// @param err_ptr the error pointer (optional).
/// @param ctx_ptr the context pointer (optional).
typedef void(* __cswiftslash_future_result_err_handler_f)(
	const uint8_t err_type,
	const __cswiftslash_optr_t err_ptr,
	const __cswiftslash_optr_t ctx_ptr
);

// - FUNCTION
/// @brief a future cancel handler function.
/// @param ctx_ptr the context pointer (optional).
typedef void(* __cswiftslash_future_result_cncl_handler_f)(
	const __cswiftslash_optr_t ctx_ptr
);

/// @brief a future that will either succeed with a pointer type and pointer, or fail with an error type and pointer.
typedef struct __cswiftslash_future {
	// internal state mechanisms for the future itself.
	_Atomic uint8_t statVal;						// internal status value.
	pthread_mutex_t mutex;							// internal mutex for the condition.
	
	// user fields related to the result.
	_Atomic uint8_t fres_val_type;					// result value type (user field).
	_Atomic __cswiftslash_optr_t fres_val;			// result value (user field).

	__cswiftslash_ptr_t wheaps;						// the fifo chain of waiters.
} __cswiftslash_future_t;

/// @brief a pointer to a future.
typedef __cswiftslash_future_t*_Nonnull _cswiftslash_future_ptr_t;

// init and deinit -----

/// @brief initialize a future.
/// @return the initialized future pointer.
_cswiftslash_future_ptr_t __cswiftslash_future_t_init(void);

/// @brief destroy a future. behavior is undefined if this is called while the future is still in use.
/// @param future a pointer to the future to deallocate.
/// @param ctx_ptr the context pointer to pass to the result handler.
/// @param res_handler the result handler to call when the future is complete.
/// @param err_handler the error handler to call when the future is complete.
/// @return void is returned after the future is safely deallocated.
void __cswiftslash_future_t_destroy(
	_cswiftslash_future_ptr_t future,
	const __cswiftslash_optr_t ctx_ptr,
	const _Nonnull __cswiftslash_future_result_val_handler_f res_handler,
	const _Nonnull __cswiftslash_future_result_err_handler_f err_handlerf
);

// waiting for the result -----

/// @brief block the calling thread until the future is complete.
/// @param future the future to wait for.
/// @param ctx_ptr the context pointer to pass to the result handler.
/// @param res_handler the result handler to call when the future is complete.
/// @param err_handler the error handler to call when the future is complete.
/// @param cancel_handler the cancel handler to call when the future is cancelled.
/// @return void is returned (calling thread is no longer blocked) when one of the result handlers is fired with the result.
void __cswiftslash_future_t_wait_sync(
	const _cswiftslash_future_ptr_t future,
	const __cswiftslash_optr_t ctx_ptr,
	const _Nonnull __cswiftslash_future_result_val_handler_f res_handler,
	const _Nonnull __cswiftslash_future_result_err_handler_f err_handler,
	const _Nonnull __cswiftslash_future_result_cncl_handler_f cancel_handler
);

/// @brief register completion handlers for the future and return immediately. handler functions will be called from the thread that completes the future.
/// @param future the future to wait for.
/// @param ctx_ptr the context pointer to pass to the result handler.
/// @param res_handler the result handler to call (from another thread) when the future is complete.
/// @param err_handler the error handler to call (from another thread) when the future is complete.
/// @param cancel_handler the cancel handler to call (from another thread) when the future is cancelled.
/// @return void is returned after the handlers are registered.
void __cswiftslash_future_t_wait_async(
	const _cswiftslash_future_ptr_t future,
	const __cswiftslash_optr_t ctx_ptr,
	const _Nonnull __cswiftslash_future_result_val_handler_f res_handler,
	const _Nonnull __cswiftslash_future_result_err_handler_f err_handler,
	const _Nonnull __cswiftslash_future_result_cncl_handler_f cancel_handler
);

// delivering the result -----

/// broadcast a completion result to all threads waiting on the future.
/// @param future the future to broadcast to.
/// @param res_type the result type - an 8 bit value.
/// @param res_val the result value - an optional pointer.
/// @return whether the broadcast was successful.
bool __cswiftslash_future_t_broadcast_res_val(
	const _cswiftslash_future_ptr_t future,
	const uint8_t res_type,
	const __cswiftslash_optr_t res_val
);

/// broadcast a completion result to all threads waiting on the future.
/// @param future the future to broadcast to.
/// @param res_type the result type - an 8 bit value.
/// @param res_val the result value - an optional pointer.
/// @return whether the broadcast was successful.
bool __cswiftslash_future_t_broadcast_res_throw(
	const _cswiftslash_future_ptr_t future,
	const uint8_t res_type,
	const __cswiftslash_optr_t res_val
);

#endif // __CLIBSWIFTSLASH_FUTURE_H