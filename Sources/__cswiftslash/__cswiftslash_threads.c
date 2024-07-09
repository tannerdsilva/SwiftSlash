// LICENSE MIT
// copyright (c) tanner silva 2024. all rights reserved.
#include "__cswiftslash_threads.h"
#include <string.h>

_cswiftslash_pthread_t_type _cswiftslash_pthread_fresh(const pthread_attr_t *_Nullable attr, void *_Nonnull(*start_routine)(void *_Nonnull), void*_Nonnull arg, int*_Nonnull result) {
	_cswiftslash_pthread_t_type newthread;
	(*result) = pthread_create(&newthread, attr, start_routine, arg);
	return newthread;
 }

_Noreturn void _cswiftslash_pthreads_main_f_run(_cswiftslash_ptr_t _Nonnull arg, const _cswiftslash_pthreads_main_f _Nonnull run, const _cswiftslash_pthreads_cancel_handler_f _Nonnull cancel_handler) {	// enable cancellation
	// set deferred cancellation state.
	pthread_setcanceltype(PTHREAD_CANCEL_DEFERRED, NULL);

	// push the function that will be called if and when the thread is cancelled.
	pthread_cleanup_push(cancel_handler, arg);

	// enable cancellation
	pthread_setcancelstate(PTHREAD_CANCEL_ENABLE, NULL);

	// check if the thread has been cancelled
	pthread_testcancel();

	// work
	run(arg);

	pthread_cleanup_pop(0); // do not fire if not cancelled

	pthread_exit(NULL);
}
