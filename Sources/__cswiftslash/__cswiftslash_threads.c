// LICENSE MIT
// copyright (c) tanner silva 2024. all rights reserved.
#include "__cswiftslash_threads.h"
#include <string.h>

_cswiftslash_pthread_t_type _cswiftslash_pthread_fresh(const pthread_attr_t *_Nullable attr, void *_Nonnull(*start_routine)(void *_Nonnull), void*_Nonnull arg, int*_Nonnull result) {
	_cswiftslash_pthread_t_type newthread;
	(*result) = pthread_create(&newthread, attr, start_routine, arg);
	return newthread;
 }

struct _cswiftslash_pthreads_dealloc_package {
	_cswiftslash_ptr_t arg;
	_cswiftslash_optr_t ptr;
	_cswiftslash_pthreads_main_dealloc_f dealloc;
 };

void _cswiftslash_pthreads_dealloc_internalf(void*arg) {
	struct _cswiftslash_pthreads_dealloc_package*package = (struct _cswiftslash_pthreads_dealloc_package*)arg;
	package->dealloc(package->arg, package->ptr);
}

_Noreturn void _cswiftslash_pthreads_main_f_run(_cswiftslash_ptr_t _Nonnull arg, const _cswiftslash_pthreads_main_f _Nonnull run, const _cswiftslash_pthreads_main_alloc_f _Nonnull main_allocator_func, const _cswiftslash_pthreads_main_dealloc_f _Nonnull main_deallocator_func, const _cswiftslash_pthreads_cancel_handler_f _Nonnull cancel_handler) {	// enable cancellation
	// push the function that will be called if and when the thread is cancelled
	pthread_cleanup_push(cancel_handler, arg);

	// allocate the workspace memory
	_cswiftslash_optr_t ptr = main_allocator_func(arg);

	struct _cswiftslash_pthreads_dealloc_package dpkg;
	dpkg.arg = arg;
	dpkg.ptr = ptr;
	dpkg.dealloc = main_deallocator_func;

	// push the function that will deallocate the workspace memory
	pthread_cleanup_push(_cswiftslash_pthreads_dealloc_internalf, &dpkg);
	
	// enable cancellation
	pthread_setcancelstate(PTHREAD_CANCEL_ENABLE, NULL);

	// check if the thread has been cancelled
	pthread_testcancel();

	// work
	run(arg, ptr);

	pthread_cleanup_pop(1); // always deallocate the pthread working memory regardless if there was a cancellation or not.
	pthread_cleanup_pop(0); // do not fire if not cancelled

	pthread_exit(arg);
}
