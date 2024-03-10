#ifndef CSWIFTSLASH_WORKTHREAD_H
#define CSWIFTSLASH_WORKTHREAD_H

#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>

typedef struct workthread {
	pthread_t thread;
} workthread_t;

typedef workthread_t* workthread_ptr_t;

/// @brief create a new workthread
/// @param wt the workthread to be initialized and started
/// @param start_routine the function to be executed by the workthread
/// @param arg the argument to be passed to the start_routine
/// @return zero on success, non-zero on failure
int wt_init(workthread_ptr_t wt, void* (*start_routine)(void*), void* arg);

/// @brief wait for the workthread to finish
/// @param wt the workthread to be waited for
/// @return	zero on success, non-zero on failure
int wt_wait(workthread_ptr_t wt);

/// @brief close the workthread and free the resources
/// @param wt the workthread to be closed
/// @return zero on success, non-zero on failure
int wt_deinit(workthread_ptr_t wt);

#endif