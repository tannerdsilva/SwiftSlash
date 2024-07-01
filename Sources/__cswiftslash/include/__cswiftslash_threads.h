// LICENSE MIT
// copyright (c) tanner silva 2024. all rights reserved.
#ifndef _CSWIFTSLASH_PTHREADS_H
#define _CSWIFTSLASH_PTHREADS_H

#include <pthread.h>
#include "__cswiftslash_types.h"
#include <sys/sem.h>

typedef pthread_t _cswiftslash_pthread_t_type;

/// makes a fresh pthread_t.
_cswiftslash_pthread_t_type _cswiftslash_pthread_fresh();

typedef void(* _cswiftslash_pthreads_main_f)(_cswiftslash_optr_t arg);
typedef void(* _cswiftslash_pthreads_cancel_handler_f)(_cswiftslash_optr_t arg);

void*_Nullable _cswiftslash_pthreads_main_f_run(_cswiftslash_ptr_t _Nonnull arg, const _cswiftslash_pthreads_main_f _Nonnull run, const _cswiftslash_pthreads_cancel_handler_f _Nonnull cancel_handler); 

#endif // _CSWIFTSLASH_PTHREADS_H