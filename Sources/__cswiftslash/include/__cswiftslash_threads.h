// LICENSE MIT
// copyright (c) tanner silva 2024. all rights reserved.
#ifndef _CSWIFTSLASH_PTHREADS_H
#define _CSWIFTSLASH_PTHREADS_H

#include <pthread.h>
#include "__cswiftslash_types.h"

#if defined(__APPLE__)
#include <dispatch/dispatch.h>
#else
#include <semaphore.h>
#endif


// MARK - semaphores

/// @brief the type of semaphore that is used on this particular platform
typedef dispatch_semaphore_t _cswiftslash_sem_t_type;

/// @brief creates a new _cswiftslash_sem that is ready for use.
_cswiftslash_sem_t_type _Nonnull _cswiftslash_sem_fresh();

/// @brief wait for a semaphore to be signaled
/// @param sem the semaphore to wait on
void _cswiftslash_sem_wait(_cswiftslash_sem_t_type _Nonnull*_Nonnull sem);

/// @brief signal a semaphore
/// @param sem the semaphore to signal
void _cswiftslash_sem_signal(_cswiftslash_sem_t_type _Nonnull*_Nonnull sem);

/// @brief destroy a semaphore
/// @param sem the semaphore to destroy
void _cswiftslash_sem_destroy(_cswiftslash_sem_t_type _Nonnull*_Nonnull sem);



// MARK - threads

/// @brief the type of pthread_t that is used on this particular platform
typedef pthread_t _cswiftslash_pthread_t_type;

/// makes a fresh pthread_t that will launch immediately
_cswiftslash_pthread_t_type _cswiftslash_pthread_fresh(const pthread_attr_t *attr, void*(*start_routine)(void *_Nonnull), void* arg, int*_Nonnull result);

typedef void(* _cswiftslash_pthreads_main_f)(_cswiftslash_optr_t arg);
typedef void(* _cswiftslash_pthreads_cancel_handler_f)(_cswiftslash_optr_t arg);

void*_Nullable _cswiftslash_pthreads_main_f_run(_cswiftslash_ptr_t _Nonnull arg, const _cswiftslash_pthreads_main_f _Nonnull run, const _cswiftslash_pthreads_cancel_handler_f _Nonnull cancel_handler); 

#endif // _CSWIFTSLASH_PTHREADS_H