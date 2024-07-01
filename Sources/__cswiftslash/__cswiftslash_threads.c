// LICENSE MIT
// copyright (c) tanner silva 2024. all rights reserved.
#include "__cswiftslash_threads.h"
#include <string.h>

 _cswiftslash_pthread_t_type _cswiftslash_pthread_fresh() {
	_cswiftslash_pthread_t_type newthread;
	return newthread;
 }

void* _cswiftslash_pthreads_main_f_run(_cswiftslash_ptr_t _Nonnull arg, const _cswiftslash_pthreads_main_f run, const _cswiftslash_pthreads_cancel_handler_f cancel_handler) {
	// enable deferred cancellation
	pthread_setcanceltype(PTHREAD_CANCEL_DEFERRED, NULL);
	// enable cancellation
	pthread_setcancelstate(PTHREAD_CANCEL_ENABLE, NULL);
	// enable cleanup
	pthread_cleanup_push((void(*)(void*))cancel_handler, arg);
	run(arg);
	pthread_cleanup_pop(0);
	return arg;
}
