/*
LICENSE MIT
copyright (c) tanner silva 2024. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

#include "__cswiftslash_threads.h"
#include <string.h>
#include <stdlib.h>

__cswiftslash_threads_config_t __cswiftslash_threads_config_garbage(void) {
	__cswiftslash_threads_config_t garbage;
	memset(&garbage, 0, sizeof(__cswiftslash_threads_config_t));
	return garbage;
}

void *_Nullable ____cswiftslash_threads_f(void *_Nonnull arg) {
	// disable cancellation so that the thread can be set up.
	pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, NULL);	// cancel not allowed right now, we must first configure the thread.
	pthread_setcanceltype(PTHREAD_CANCEL_DEFERRED, NULL);	// deferred cancellation only.

	__cswiftslash_threads_config_t cfg = *((__cswiftslash_threads_config_t*)arg);	// copy the configuration into a local stack variable.
	free(arg);	// deallocate the configuration argument from the heap.
	
	// pass the initial arguments into the allocator. this is the only time that the initial arguments will be accessible. the work thread is responsible for transferring any necessary data to the workspace.
	const __cswiftslash_ptr_t wsptr = cfg.alloc_f(cfg.alloc_arg);	// alloc_arg is now considered deallocated space, do not touch.

	// push the cleanup handlers for this thread.
	pthread_cleanup_push(cfg.dealloc_f, wsptr);		// push workspace deallocator
	pthread_cleanup_push(cfg.cancel_f, wsptr);		// push cancel handler

	// enable cancellation.
	pthread_setcancelstate(PTHREAD_CANCEL_ENABLE, NULL);

	// check if the thread has been cancelled.
	pthread_testcancel();

	// work begin
	cfg.run_f(wsptr);
	// work complete (this would not be reached if the pthread was cancelled during run_f)

	// pop the cancel handler and workspace deallocator
	pthread_cleanup_pop(0);		// pop cancel handler (do not fire here)
	pthread_cleanup_pop(1);		// pop workspace deallocator (always fire here)

	return NULL;
}

 __cswiftslash_threads_config_t *_Nonnull __cswiftslash_threads_config_init (
	__cswiftslash_ptr_t alloc_arg,
	__cswiftslash_threads_alloc_f _Nonnull alloc_f,
	__cswiftslash_threads_main_f _Nonnull run_f,
	__cswiftslash_threads_cancel_f _Nonnull cancel_f,
	__cswiftslash_threads_dealloc_f _Nonnull dealloc_f
) {
	__cswiftslash_threads_config_t *config = malloc(sizeof(__cswiftslash_threads_config_t));
	(*config) = (__cswiftslash_threads_config_t) {
		.alloc_arg = alloc_arg,
		.alloc_f = alloc_f,
		.run_f = run_f,
		.cancel_f = cancel_f,
		.dealloc_f = dealloc_f
	};
	return config;
}

__cswiftslash_threads_t_type __cswiftslash_threads_config_run(
	const __cswiftslash_threads_config_t *_Nonnull config_consume,
	int *_Nonnull result
) {
	// launch the new thread, pass the consuming pointer as an argument.
	__cswiftslash_threads_t_type newthread;
	memset(&newthread, 0, sizeof(__cswiftslash_threads_t_type));
	(*result) = pthread_create(&newthread, NULL, ____cswiftslash_threads_f, (void*)config_consume);
	if ((*result) != 0) {
		free((void*)config_consume);
	}
	return newthread;
}