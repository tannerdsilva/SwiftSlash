// LICENSE MIT
// copyright (c) tanner silva 2024. all rights reserved.
#ifndef _CSWIFTSLASH_PTHREADS_H
#define _CSWIFTSLASH_PTHREADS_H

#include <pthread.h>
#include <stdnoreturn.h>
#include "__cswiftslash_types.h"
#include <stdnoreturn.h>

#if defined(__APPLE__)
typedef pthread_t _Nullable _cswiftslash_pthread_t_type;
#else
typedef pthread_t _cswiftslash_pthread_t_type;
#endif

// MARK - threads

/// @brief the type of pthread_t that is used on this particular platform

/// makes a fresh pthread_t that will launch immediately
_cswiftslash_pthread_t_type _cswiftslash_pthread_fresh(const pthread_attr_t *_Nullable attr, void *_Nonnull(*_Nonnull start_routine)(void *_Nonnull), void*_Nonnull arg, int*_Nonnull result);

/// @brief the type of a pthread main function.
typedef void(*_cswiftslash_pthreads_main_f)(_cswiftslash_ptr_t arg);

/// @brief a cancel handler for a pthread.
typedef void(* _cswiftslash_pthreads_cancel_handler_f)(_cswiftslash_ptr_t arg);

/// @brief runs a pthread with a main function and a cancel handler.
/// @param arg the argument pointer to pass to the main function.
/// @param alloc the workspace allocator to run.
/// @param run the main function to run.
/// @param dealloc the workspace deallocator to run.
/// @param cancel_handler the cancel handler to run if the thread is cancelled.
/// @note this function will never return, it is meant to be the main driver for a pthread.
_Noreturn void _cswiftslash_pthreads_main_f_run(_cswiftslash_ptr_t arg, const _cswiftslash_pthreads_main_f _Nonnull run, const _cswiftslash_pthreads_cancel_handler_f _Nonnull cancel_handler); 

#endif // _CSWIFTSLASH_PTHREADS_H