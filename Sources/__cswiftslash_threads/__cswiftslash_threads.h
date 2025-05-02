/*
LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

#ifndef __CLIBSWIFTSLASH_THREADS_H
#define __CLIBSWIFTSLASH_THREADS_H

#include "__cswiftslash_types.h"
#include <pthread.h>

#ifdef __APPLE__
typedef pthread_t _Nonnull __cswiftslash_threads_t_type;
#else
typedef pthread_t __cswiftslash_threads_t_type;
#endif

/// a type that describes a function that will be run as the main function of a pthread.
/// @param ws a pointer to the workspace that the pthread will use.
typedef void(* __cswiftslash_threads_main_f)(__cswiftslash_ptr_t ws);

/// an allocator for a pthread workspace.
/// @param arg the argument that was initially passed into the pthread. you can assume this is the only time you will be able to access this argument.
/// @return a pointer to the allocated workspace that the pthread will use.
typedef __cswiftslash_ptr_t(* __cswiftslash_threads_alloc_f)(__cswiftslash_ptr_t arg);

/// a deallocator for a thread workspace.
/// @param ws a pointer to the workspace that the pthread used.
typedef void(* __cswiftslash_threads_dealloc_f)(__cswiftslash_ptr_t ws);

/// a cancel handler for a pthread. this is guaranteed to be called before the workspace deallocator.
/// @param ws a pointer to the workspace that the pthread used.
typedef void(* __cswiftslash_threads_cancel_f)(__cswiftslash_ptr_t ws);

/// a configuration for a pthread. this structure outlines the standardized way that work threads are created and managed.
typedef struct __cswiftslash_threads_config_t {
	__cswiftslash_ptr_t ____aa;
	__cswiftslash_threads_alloc_f _Nonnull ____af;
	__cswiftslash_threads_main_f _Nonnull ____mf;
	__cswiftslash_threads_cancel_f _Nonnull ____cr;
	__cswiftslash_threads_dealloc_f _Nonnull ____df;
} __cswiftslash_threads_config_t;

/// create a pthread configuration.
/// @param _ the argument to pass into the workspace allocator function.
/// @param __ the workspace allocator to run.
/// @param ___ the main function to run as the 'work' of the pthread.
/// @param ____ the cancel handler to run if the thread is cancelled.
/// @param _____ the workspace deallocator to run.
__cswiftslash_threads_config_t *_Nonnull __cswiftslash_threads_config_init (
	__cswiftslash_ptr_t _,
	__cswiftslash_threads_alloc_f _Nonnull __,
	__cswiftslash_threads_main_f _Nonnull ___,
	__cswiftslash_threads_cancel_f _Nonnull ____,
	__cswiftslash_threads_dealloc_f _Nonnull _____
);

/// create a new pthread.
/// @param _ the configuration to use for the pthread lifecycle. this pointer will be freed internally by this function.
/// @param __ the result of the pthread creation.
/// @return the pthread that was created if result is 0, undefined otherwise.
__cswiftslash_threads_t_type __cswiftslash_threads_config_run(
	const __cswiftslash_threads_config_t *_Nonnull _,
	int *_Nonnull __
);

#endif // __CLIBSWIFTSLASH_THREADS_H