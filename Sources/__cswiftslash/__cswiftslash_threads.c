// LICENSE MIT
// copyright (c) tanner silva 2024. all rights reserved.
#include "__cswiftslash_threads.h"
#include <string.h>

_cswiftslash_sem_t_type _Nonnull _cswiftslash_sem_fresh(uint32_t value) {
	_cswiftslash_sem_t_type newType = dispatch_semaphore_create(value);
	return newType;
}
void _cswiftslash_sem_wait(_cswiftslash_sem_t_type* _Nonnull sem) {
	dispatch_semaphore_wait((*sem), DISPATCH_TIME_FOREVER);
}
void _cswiftslash_sem_signal(_cswiftslash_sem_t_type* _Nonnull sem) {
	dispatch_semaphore_signal((*sem));
}
void _cswiftslash_sem_destroy(_cswiftslash_sem_t_type* _Nonnull sem) {
	dispatch_release((*sem));
}

_cswiftslash_pthread_t_type _cswiftslash_pthread_fresh(const pthread_attr_t *_Nullable attr, void *_Nonnull(*start_routine)(void *_Nonnull), void*_Nonnull arg, int*_Nonnull result) {
	_cswiftslash_pthread_t_type newthread;
	(*result) = pthread_create(&newthread, attr, start_routine, arg);
	return newthread;
 }

void*_Nullable _cswiftslash_pthreads_main_f_run(_cswiftslash_ptr_t _Nonnull arg, const _cswiftslash_pthreads_main_f _Nonnull run, const _cswiftslash_pthreads_main_alloc_f _Nonnull main_allocator_func, const _cswiftslash_pthreads_main_dealloc_f _Nonnull main_deallocator_func, const _cswiftslash_pthreads_cancel_handler_f _Nonnull cancel_handler) {	// enable cancellation
	pthread_setcancelstate(PTHREAD_CANCEL_ENABLE, NULL);
	// enable deferred cancellation
	pthread_setcanceltype(PTHREAD_CANCEL_DEFERRED, NULL);

	// push the function that will be called if and when the thread is cancelled
	pthread_cleanup_push(cancel_handler, arg);

	// allocate the workspace memory
	_cswiftslash_optr_t ptr;
	main_allocator_func(&ptr);

	// push the function that will deallocate the workspace memory
	pthread_cleanup_push(main_deallocator_func, ptr);

	// work
	run(arg, ptr);

	pthread_cleanup_pop(1); // always deallocate the pthread working memory regardless if there was a cancellation or not.
	pthread_cleanup_pop(0); // do not fire if not cancelled

	// return the original argument
	return arg;
}
