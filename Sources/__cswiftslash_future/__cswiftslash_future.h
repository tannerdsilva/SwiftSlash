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
/// result handler function.
/// @param _ result type field.
/// @param __ result pointer field (optional).
/// @param ___ function context pointer (optional).
typedef void(* __cswiftslash_future_result_val_handler_f)(
	const uint8_t _,
	const __cswiftslash_optr_t __,
	const __cswiftslash_optr_t ___
);

/// error handler function.
/// @param _ error type field.
/// @param __ error pointer field (optional).
/// @param ___ function context pointer (optional).
typedef void(* __cswiftslash_future_result_err_handler_f)(
	const uint8_t _,
	const __cswiftslash_optr_t __,
	const __cswiftslash_optr_t ___
);

/// cancel handler function.
/// @param _ function context pointer (optional).
typedef void(* __cswiftslash_future_result_cncl_handler_f)(
	const __cswiftslash_optr_t _
);

/// a future that will either succeed with a pointer type and pointer, or fail with an error type and pointer.
typedef struct __cswiftslash_future {
	// internal status
	_Atomic uint8_t ____s;
	// internal mutex
	pthread_mutex_t ____m;
	
	// result type
	_Atomic uint8_t ____rt;
	// result value
	_Atomic __cswiftslash_optr_t ____rv;

	// waiters
	__cswiftslash_ptr_t ____wi;
} __cswiftslash_future_t;

/// a pointer to a future.
typedef __cswiftslash_future_t*_Nonnull __cswiftslash_future_ptr_t;

/// initialize a future.
/// @return pointer to the heap space containing the newly initialized future.
__cswiftslash_future_ptr_t __cswiftslash_future_t_init();

/// destroy a future. behavior is undefined if this is called while the future is still in use.
/// @param _ pointer to the future to deallocate.
/// @param __ the context pointer to pass to the result handler.
/// @param ___ the result handler to call when the future is complete.
/// @param ____ the error handler to call when the future is complete.
/// @return void is returned after the future is safely deallocated.
void __cswiftslash_future_t_destroy(
	__cswiftslash_future_ptr_t _,
	const __cswiftslash_optr_t __,
	const _Nonnull __cswiftslash_future_result_val_handler_f ___,
	const _Nonnull __cswiftslash_future_result_err_handler_f ____
);

/// block the calling thread until the future is complete.
/// @param _ the future to wait for.
/// @param __ the context pointer to pass to the result handler.
/// @param ___ the result handler to call when the future is complete.
/// @param ____ the error handler to call when the future is complete.
/// @param _____ the cancel handler to call when the future is cancelled.
/// @return void is returned (calling thread is no longer blocked) when one of the result handlers is fired with the result.
void __cswiftslash_future_t_wait_sync(
	const __cswiftslash_future_ptr_t _,
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
/// @return a unique identifier for the waiter. this unique identifier can be used to cancel the waiter later. if the future is already complete, the result handler will be called immediately, and zero is returned.
uint64_t __cswiftslash_future_t_wait_async(
	const __cswiftslash_future_ptr_t _,
	const __cswiftslash_optr_t __,
	const _Nonnull __cswiftslash_future_result_val_handler_f ___,
	const _Nonnull __cswiftslash_future_result_err_handler_f ____,
	const _Nonnull __cswiftslash_future_result_cncl_handler_f _____
);

/// cancel an asynchronous waiter for a future. after calling this function, you can rest assured that the result handlers will not be fired for the specified waiter. however, it is possible that a result becomes available during the course of calling this function, and such conditions are reported by the return value.
/// @param _ the future to cancel the waiter for.
/// @param __ the unique waiter identifier to cancel.
/// @return a boolean value indicating if the cancellation was successful. if the waiter was already complete and the handler functions were fired, this function will return false.
bool __cswiftslash_future_t_wait_async_invalidate(
	const __cswiftslash_future_ptr_t _,
	const uint64_t __
);

/// broadcast a completion result to all threads waiting on the future.
/// @param _ the future to broadcast to.
/// @param __ the result type - an 8 bit value.
/// @param ___ the result value - an optional pointer.
/// @return whether the broadcast was successful.
bool __cswiftslash_future_t_broadcast_res_val(
	const __cswiftslash_future_ptr_t _,
	const uint8_t __,
	const __cswiftslash_optr_t ___
);

/// broadcast a completion result to all threads waiting on the future.
/// @param _ the future to broadcast to.
/// @param __ the result type - an 8 bit value.
/// @param ___ the result value - an optional pointer.
/// @return whether the broadcast was successful.
bool __cswiftslash_future_t_broadcast_res_throw(
	const __cswiftslash_future_ptr_t _,
	const uint8_t __,
	const __cswiftslash_optr_t ___
);

/// broadcast a cancellation result to all threads waiting on the future.
/// @param _ the future to broadcast to.
/// @return whether the broadcast was successful.
bool __cswiftslash_future_t_broadcast_cancel(
	const __cswiftslash_future_ptr_t _
);

#endif // __CLIBSWIFTSLASH_FUTURE_H