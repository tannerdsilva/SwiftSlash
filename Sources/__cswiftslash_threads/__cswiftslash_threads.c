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

__cswiftslash_threads_config_t __cswiftslash_threads_config_garbage() {
	__cswiftslash_threads_config_t garbage;
	memset(&garbage, 0, sizeof(__cswiftslash_threads_config_t));
	return garbage;
}

void *_Nullable ____cswiftslash_threads_f(void *_Nonnull _) {
	// disable cancellation so that the thread can be set up. THIS QUICK ENABLE/DISABLE MIGHT BE DUMB AND FRIVILOUS BUT HERE I AM DOING IT ANYWAY.
	pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, NULL);	// cancel not allowed right now, we must first configure the thread.
	pthread_setcanceltype(PTHREAD_CANCEL_DEFERRED, NULL);	// deferred cancellation only.

	__cswiftslash_threads_config_t __0 = *((__cswiftslash_threads_config_t*)_);	// copy the configuration into a local stack variable.
	free(_);	// deallocate the configuration argument from the heap.
	
	// pass the initial arguments into the allocator. this is the only time that the initial arguments will be accessible. the work thread is responsible for transferring any necessary data to the workspace.
	const __cswiftslash_ptr_t __1 = __0.____af(__0.____aa);	// alloc_arg is now considered deallocated space, do not touch.

	// push the cleanup handlers for this thread.
	pthread_cleanup_push(__0.____df, __1);		// push workspace deallocator
	pthread_cleanup_push(__0.____cr, __1);		// push cancel handler

	// enable cancellation.
	pthread_setcancelstate(PTHREAD_CANCEL_ENABLE, NULL);

	// check if the thread has been cancelled.
	pthread_testcancel();

	// work begin
	__0.____mf(__1);
	// work complete (this would not be reached if the pthread was cancelled during run_f)

	// pop the cancel handler and workspace deallocator
	pthread_cleanup_pop(0);		// pop cancel handler (do not fire here)
	pthread_cleanup_pop(1);		// pop workspace deallocator (always fire here)

	return NULL;
}

 __cswiftslash_threads_config_t *_Nonnull __cswiftslash_threads_config_init (
	__cswiftslash_ptr_t _,
	__cswiftslash_threads_alloc_f _Nonnull __,
	__cswiftslash_threads_main_f _Nonnull ___,
	__cswiftslash_threads_cancel_f _Nonnull ____,
	__cswiftslash_threads_dealloc_f _Nonnull _____
) {
	__cswiftslash_threads_config_t *__0 = malloc(sizeof(__cswiftslash_threads_config_t));
	(*__0) = (__cswiftslash_threads_config_t) {
		.____aa = _,
		.____af = __,
		.____mf = ___,
		.____cr = ____,
		.____df = _____
	};
	return __0;
}

__cswiftslash_threads_t_type __cswiftslash_threads_config_run(
	const __cswiftslash_threads_config_t *_Nonnull _,
	int *_Nonnull __
) {
	// launch the new thread, pass the consuming pointer as an argument.
	__cswiftslash_threads_t_type __0;
	memset(&__0, 0, sizeof(__cswiftslash_threads_t_type));
	(*__) = pthread_create(&__0, NULL, ____cswiftslash_threads_f, (void*)_);
	if ((*__) != 0) {
		free((void*)_);
	}
	return __0;
}