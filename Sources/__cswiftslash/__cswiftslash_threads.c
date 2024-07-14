// LICENSE MIT
// copyright (c) tanner silva 2024. all rights reserved.
#include "__cswiftslash_threads.h"
#include <signal.h>
#include <string.h>
#include <pthread.h>

void *_Nullable _cswiftslash_pthread_f(void *_Nonnull arg) {
	// disable cancellation so that the thread can be set up.
	pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, NULL);	// cancel not allowed right now, we must first configure the thread.
	pthread_setcanceltype(PTHREAD_CANCEL_DEFERRED, NULL);	// deferred cancellation only.

	_cswiftslash_pthread_config_t cfg = *((_cswiftslash_pthread_config_t*)arg);	// copy the configuration into a local stack variable.
	
	// pass the initial arguments into the allocator. this is the only time that the initial arguments will be accessible. the work thread is responsible for transferring any necessary data to the workspace.
	const _cswiftslash_ptr_t wsptr = cfg.alloc_f(cfg.alloc_arg);	// alloc_arg is now considered deallocated space, do not touch.

	// push the cleanup handlers for this thread.
	pthread_cleanup_push(cfg.dealloc_f, wsptr);		// push workspace deallocator
	pthread_cleanup_push(cfg.cancel_f, wsptr);		// push cancel handler

	// enable cancellation.
	pthread_setcancelstate(PTHREAD_CANCEL_ENABLE, NULL);

	// check if the thread has been cancelled.
	pthread_testcancel();

	// work
	cfg.run_f(wsptr);

	// pop the cancel handler and workspace deallocator
	pthread_cleanup_pop(0);		// pop cancel handler (do not fire)
	pthread_cleanup_pop(1);		// pop workspace deallocator (fire)

	return NULL;
}

 _cswiftslash_pthread_config_t _cswiftslash_pthread_config_init (
	_cswiftslash_ptr_t alloc_arg,
	_cswiftslash_pthreads_alloc_f _Nonnull alloc_f,
	_cswiftslash_pthreads_main_f _Nonnull run_f,
	_cswiftslash_pthreads_cancel_f _Nonnull cancel_f,
	_cswiftslash_pthreads_dealloc_f _Nonnull dealloc_f
) {
	return (_cswiftslash_pthread_config_t) {
		.alloc_arg = alloc_arg,
		.alloc_f = alloc_f,
		.run_f = run_f,
		.cancel_f = cancel_f,
		.dealloc_f = dealloc_f
	};
}

_cswiftslash_pthread_t_type _cswiftslash_pthread_config_run(
	const _cswiftslash_pthread_config_t *_Nonnull config_consume,
	int*_Nonnull result
) {
	// launch the new thread, pass the consuming pointer as an argument.
	_cswiftslash_pthread_t_type newthread;
	memset(&newthread, 0, sizeof(_cswiftslash_pthread_t_type));
	(*result) = pthread_create(&newthread, NULL, _cswiftslash_pthread_f, (void*)config_consume);
	return newthread;
}