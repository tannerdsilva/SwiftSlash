// LICENSE MIT
// copyright (c) tanner silva 2024. all rights reserved.
#include "__cswiftslash_threads.h"
#include <string.h>

pthread_t cswiftslash_pthread_init() {
	pthread_t thread;
	memset(&thread, 0, sizeof(pthread_t));
	return thread;
}
