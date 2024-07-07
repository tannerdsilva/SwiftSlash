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

typedef void(* _cswiftslash_pthreads_main_f)(_cswiftslash_ptr_t arg, _cswiftslash_ptr_t allocated);
typedef void(* _cswiftslash_pthreads_main_alloc_f)(_cswiftslash_ptr_t arg, _cswiftslash_optr_t *_Nonnull allocated);
typedef void(* _cswiftslash_pthreads_main_dealloc_f)(_cswiftslash_ptr_t arg, _cswiftslash_optr_t allocated);
typedef void(* _cswiftslash_pthreads_cancel_handler_f)(_cswiftslash_ptr_t arg);

_Noreturn void _cswiftslash_pthreads_main_f_run(_cswiftslash_ptr_t _Nonnull arg, const _cswiftslash_pthreads_main_f _Nonnull run, const _cswiftslash_pthreads_main_alloc_f _Nonnull main_allocator_func, const _cswiftslash_pthreads_main_dealloc_f _Nonnull main_deallocator_func, const _cswiftslash_pthreads_cancel_handler_f _Nonnull cancel_handler); 

#endif // _CSWIFTSLASH_PTHREADS_H