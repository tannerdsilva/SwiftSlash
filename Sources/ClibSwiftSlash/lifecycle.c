#include "lifecycle.h"
#include <stdatomic.h>

const size_t _so_pid = sizeof(pid_t);

lifecyclestore_ptr_t lc_init() {
	lifecyclestore_ptr_t newLC = malloc(sizeof(lifecyclestore_t));
	atomic_store(&newLC->sync, 0);
	hashmap_create(4, &newLC->heapstore);
	return newLC;
}

int lc_launch(lifecyclestore_ptr_t lc, terminationgroup_ptr_t tg) {
	void* pidptr = tg_pid_ptr(tg);
	int syncVal = atomic_load_explicit(&lc->sync, memory_order_acquire);
	int retval = hashmap_put(&lc->heapstore, pidptr, _so_pid, tg);
	atomic_store_explicit(&lc->sync, sync, memory_order_release);
	return retval;
}

int lc_exit(lifecyclestore_ptr_t lc, pid_t pid, int code) {
	pid_t localPid = pid;
	int syncVal = atomic_load_explicit(&lc->sync, memory_order_acquire);
	terminationgroup_ptr_t tg = hashmap_get(&lc->heapstore, (const char*)&pid, _so_pid);
	int retval = hashmap_remove(&lc->heapstore, (const char*)&pid, _so_pid);
	if (retval == 0) {
		retval += tg_exit(tg, code);
	}
	atomic_store_explicit(&lc->sync, syncVal, memory_order_release);
	return retval;
}

int lc_signal(lifecyclestore_ptr_t lc, pid_t pid, int code) {
	int syncVal = atomic_load_explicit(&lc->sync, memory_order_acquire);
	terminationgroup_ptr_t tg = hashmap_get(&lc->heapstore, (const char*)&pid, _so_pid);
	int retval = hashmap_remove(&lc->heapstore, (const char*)&pid, _so_pid);
	if (retval == 0) {
		retval += tg_signal(tg, code);
	}
	atomic_store_explicit(&lc->sync, syncVal, memory_order_release);
	return retval;
}

void lc_dealloc(lifecyclestore_ptr_t lc) {
	hashmap_destroy(&lc->heapstore);
	free(lc);
}
