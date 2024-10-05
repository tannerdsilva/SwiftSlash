// LICENSE MIT
// copyright (c) tanner silva 2024. all rights reserved.
#ifndef _CSWIFTSLASH_PTHREADS_H
#define _CSWIFTSLASH_PTHREADS_H

#include <pthread.h>
#include <signal.h>
#include "__cswiftslash_types.h"

#if defined(__APPLE__)
typedef pthread_t _Nonnull _cswiftslash_pthread_t_type;
#else
typedef pthread_t _cswiftslash_pthread_t_type;
#endif

/// @brief the type of a pthread main function.
/// @param ws a pointer to the workspace that the pthread will use.
typedef void(*_cswiftslash_pthreads_main_f)(_cswiftslash_ptr_t ws);

/// @brief an allocator for a pthread workspace.
/// @param arg the argument that was initially passed into the pthread. you can assume this is the only time you will be able to access this argument.
/// @return a pointer to the allocated workspace that the pthread will use.
typedef _cswiftslash_ptr_t(* _cswiftslash_pthreads_alloc_f)(_cswiftslash_ptr_t arg);

/// @brief a deallocator for a pthread workspace.
/// @param ws a pointer to the workspace that the pthread used.
typedef void(* _cswiftslash_pthreads_dealloc_f)(_cswiftslash_ptr_t ws);

/// @brief a cancel handler for a pthread. this is guaranteed to be called before the workspace deallocator.
/// @param ws a pointer to the workspace that the pthread used.
typedef void(* _cswiftslash_pthreads_cancel_f)(_cswiftslash_ptr_t ws);

/// @brief a configuration for a pthread. this structure outlines the standardized way that work threads are created and managed.
typedef struct _cswiftslash_pthread_config_t {
	_cswiftslash_ptr_t alloc_arg;
	_cswiftslash_pthreads_alloc_f _Nonnull alloc_f;
	_cswiftslash_pthreads_main_f _Nonnull run_f;
	_cswiftslash_pthreads_cancel_f _Nonnull cancel_f;
	_cswiftslash_pthreads_dealloc_f _Nonnull dealloc_f;
} _cswiftslash_pthread_config_t;

/// @brief create a pthread configuration.
/// @param alloc_arg the argument to pass into the workspace allocator function.
/// @param alloc_f the workspace allocator to run.
/// @param run_f the main function to run as the 'work' of the pthread.
/// @param cancel_f the cancel handler to run if the thread is cancelled.
/// @param dealloc_f the workspace deallocator to run.
_cswiftslash_pthread_config_t *_Nonnull _cswiftslash_pthread_config_init (
	_cswiftslash_ptr_t alloc_arg,
	_cswiftslash_pthreads_alloc_f _Nonnull alloc_f,
	_cswiftslash_pthreads_main_f _Nonnull run_f,
	_cswiftslash_pthreads_cancel_f _Nonnull cancel_f,
	_cswiftslash_pthreads_dealloc_f _Nonnull dealloc_f
);

/// @brief create a new pthread.
/// @param config_consume the configuration to use for the pthread lifecycle. this pointer will be freed internally by this function.
/// @param result the result of the pthread creation.
/// @return the pthread that was created if result is 0, undefined otherwise.
_cswiftslash_pthread_t_type _cswiftslash_pthread_config_run(
	const _cswiftslash_pthread_config_t *_Nonnull config,
	int *_Nonnull result
 );

#endif // _CSWIFTSLASH_PTHREADS_H