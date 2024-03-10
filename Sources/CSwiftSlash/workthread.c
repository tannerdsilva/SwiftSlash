#include "workthread.h"
int wt_init(workthread_t* wt, void*(*work)(void*), void* arg) {
	return pthread_create(&wt->thread, NULL, work, arg);
}
int wt_wait(workthread_t* wt) {
	return pthread_join(wt->thread, NULL);
}
int wt_deinit(workthread_t* wt) {
	pthread_cancel(wt->thread);
	return pthread_join(wt->thread, NULL);
}