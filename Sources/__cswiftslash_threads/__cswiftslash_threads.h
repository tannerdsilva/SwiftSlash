/*
LICENSE MIT
copyright (c) tanner silva 2024. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

#ifndef __CSWIFTSLASH_THREADS_H
#define __CSWIFTSLASH_THREADS_H

#include "__cswiftslash_types.h"
#include <pthread.h>

#if defined(__APPLE__)
typedef pthread_t _Nonnull __cswiftslash_threads_t_type;
#else
typedef pthread_t __cswiftslash_thread_t_type;
#endif

/// @brief a type that describes a function that will be run as the main function of a pthread.
/// @param ws a pointer to the workspace that the pthread will use.
typedef void(* __cswiftslash_threads_main_f)(__cswiftslash_ptr_t ws);

/// @brief an allocator for a pthread workspace.
/// @param arg the argument that was initially passed into the pthread. you can assume this is the only time you will be able to access this argument.
/// @return a pointer to the allocated workspace that the pthread will use.
typedef __cswiftslash_ptr_t(* __cswiftslash_threads_alloc_f)(__cswiftslash_ptr_t arg);

/// @brief a deallocator for a thread workspace.
/// @param ws a pointer to the workspace that the pthread used.
typedef void(* __cswiftslash_threads_dealloc_f)(__cswiftslash_ptr_t ws);

/// @brief a cancel handler for a pthread. this is guaranteed to be called before the workspace deallocator.
/// @param ws a pointer to the workspace that the pthread used.
typedef void(* __cswiftslash_threads_cancel_f)(__cswiftslash_ptr_t ws);

/// @brief a configuration for a pthread. this structure outlines the standardized way that work threads are created and managed.
typedef struct __cswiftslash_threads_config_t {
	__cswiftslash_ptr_t alloc_arg;
	__cswiftslash_threads_alloc_f _Nonnull alloc_f;
	__cswiftslash_threads_main_f _Nonnull run_f;
	__cswiftslash_threads_cancel_f _Nonnull cancel_f;
	__cswiftslash_threads_dealloc_f _Nonnull dealloc_f;
} __cswiftslash_threads_config_t;

/// @brief create a pthread configuration.
/// @param alloc_arg the argument to pass into the workspace allocator function.
/// @param alloc_f the workspace allocator to run.
/// @param run_f the main function to run as the 'work' of the pthread.
/// @param cancel_f the cancel handler to run if the thread is cancelled.
/// @param dealloc_f the workspace deallocator to run.
__cswiftslash_threads_config_t *_Nonnull __cswiftslash_threads_config_init (
	__cswiftslash_ptr_t alloc_arg,
	__cswiftslash_threads_alloc_f _Nonnull alloc_f,
	__cswiftslash_threads_main_f _Nonnull run_f,
	__cswiftslash_threads_cancel_f _Nonnull cancel_f,
	__cswiftslash_threads_dealloc_f _Nonnull dealloc_f
);

/// @brief create a new pthread.
/// @param config_consume the configuration to use for the pthread lifecycle. this pointer will be freed internally by this function.
/// @param result the result of the pthread creation.
/// @return the pthread that was created if result is 0, undefined otherwise.
__cswiftslash_threads_t_type __cswiftslash_threads_config_run(
	const __cswiftslash_threads_config_t *_Nonnull config,
	int *_Nonnull result
);

#endif // __CSWIFTSLASH_THREADS_H