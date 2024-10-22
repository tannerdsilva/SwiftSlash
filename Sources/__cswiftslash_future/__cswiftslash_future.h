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
/// a future result handler function.
/// @param _ the result type value.
/// @param __ the result pointer (optional).
/// @param ___ the context pointer (optional).
typedef void(* __cswiftslash_future_result_val_handler_f)(
	const uint8_t _,
	const __cswiftslash_optr_t __,
	const __cswiftslash_optr_t ___
);

// ERROR
// - FUNCTION
/// a future error handler function.
/// @param _ the error type value.
/// @param __ the error pointer (optional).
/// @param ___ the context pointer (optional).
typedef void(* __cswiftslash_future_result_err_handler_f)(
	const uint8_t _,
	const __cswiftslash_optr_t __,
	const __cswiftslash_optr_t ___
);

// - FUNCTION
/// a future cancel handler function.
/// @param _ the context pointer (optional).
typedef void(* __cswiftslash_future_result_cncl_handler_f)(
	const __cswiftslash_optr_t _
);

/// a future that will either succeed with a pointer type and pointer, or fail with an error type and pointer.
typedef struct __cswiftslash_future {
	// internal state mechanisms for the future itself.
	_Atomic uint8_t ____s;							// internal status value.
	pthread_mutex_t ____m;							// internal mutex for the condition.
	
	// user fields related to the result.
	_Atomic uint8_t ____rt;					// result value type (user field).
	_Atomic __cswiftslash_optr_t ____rv;	// result value (user field).

	__cswiftslash_ptr_t ____w;						// the fifo chain of waiters.
} __cswiftslash_future_t;

/// a pointer to a future.
typedef __cswiftslash_future_t*_Nonnull _cswiftslash_future_ptr_t;

// init and deinit -----

/// initialize a future.
/// @return the initialized future pointer.
_cswiftslash_future_ptr_t __cswiftslash_future_t_init();

/// destroy a future. behavior is undefined if this is called while the future is still in use.
/// @param _ a pointer to the future to deallocate.
/// @param __ the context pointer to pass to the result handler.
/// @param ___ the result handler to call when the future is complete.
/// @param ____ the error handler to call when the future is complete.
/// @return void is returned after the future is safely deallocated.
void __cswiftslash_future_t_destroy(
	_cswiftslash_future_ptr_t _,
	const __cswiftslash_optr_t __,
	const _Nonnull __cswiftslash_future_result_val_handler_f ___,
	const _Nonnull __cswiftslash_future_result_err_handler_f ____
);

// waiting for the result -----

/// block the calling thread until the future is complete.
/// @param _ the future to wait for.
/// @param __ the context pointer to pass to the result handler.
/// @param ___ the result handler to call when the future is complete.
/// @param ____ the error handler to call when the future is complete.
/// @param _____ the cancel handler to call when the future is cancelled.
/// @return void is returned (calling thread is no longer blocked) when one of the result handlers is fired with the result.
void __cswiftslash_future_t_wait_sync(
	const _cswiftslash_future_ptr_t _,
	const __cswiftslash_optr_t __,
	const _Nonnull __cswiftslash_future_result_val_handler_f ___,
	const _Nonnull __cswiftslash_future_result_err_handler_f ____,
	const _Nonnull __cswiftslash_future_result_cncl_handler_f _____
);

/// register completion handlers for the future and return immediately. handler functions will be called from the thread that completes the future.
/// @param _ the future to wait for.
/// @param __ the context pointer to pass to the result handler.
/// @param ___ the result handler to call (from another thread) when the future is complete.
/// @param ____ the error handler to call (from another thread) when the future is complete.
/// @param _____ the cancel handler to call (from another thread) when the future is cancelled.
/// @return void is returned after the handlers are registered.
void __cswiftslash_future_t_wait_async(
	const _cswiftslash_future_ptr_t _,
	const __cswiftslash_optr_t __,
	const _Nonnull __cswiftslash_future_result_val_handler_f ___,
	const _Nonnull __cswiftslash_future_result_err_handler_f ____,
	const _Nonnull __cswiftslash_future_result_cncl_handler_f _____
);

// delivering the result -----

/// broadcast a completion result to all threads waiting on the future.
/// @param _ the future to broadcast to.
/// @param __ the result type - an 8 bit value.
/// @param ___ the result value - an optional pointer.
/// @return whether the broadcast was successful.
bool __cswiftslash_future_t_broadcast_res_val(
	const _cswiftslash_future_ptr_t _,
	const uint8_t __,
	const __cswiftslash_optr_t ___
);

/// broadcast a completion result to all threads waiting on the future.
/// @param _ the future to broadcast to.
/// @param __ the result type - an 8 bit value.
/// @param ___ the result value - an optional pointer.
/// @return whether the broadcast was successful.
bool __cswiftslash_future_t_broadcast_res_throw(
	const _cswiftslash_future_ptr_t _,
	const uint8_t __,
	const __cswiftslash_optr_t ___
);

#endif // __CLIBSWIFTSLASH_FUTURE_H