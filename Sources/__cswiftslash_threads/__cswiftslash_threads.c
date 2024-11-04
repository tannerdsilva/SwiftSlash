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
	pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, NULL);
	pthread_setcanceltype(PTHREAD_CANCEL_DEFERRED, NULL);
	__cswiftslash_threads_config_t __0 = *((__cswiftslash_threads_config_t*)_);
	free(_);
	const __cswiftslash_ptr_t __1 = __0.____af(__0.____aa);
	pthread_cleanup_push(__0.____df, __1);
	pthread_cleanup_push(__0.____cr, __1);
	pthread_setcancelstate(PTHREAD_CANCEL_ENABLE, NULL);
	pthread_testcancel();
	__0.____mf(__1);
	pthread_cleanup_pop(0);
	pthread_cleanup_pop(1);
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
	__cswiftslash_threads_t_type __0;
	memset(&__0, 0, sizeof(__cswiftslash_threads_t_type));
	(*__) = pthread_create(&__0, NULL, ____cswiftslash_threads_f, (void*)_);
	if ((*__) != 0) {
		free((void*)_);
	}
	return __0;
}