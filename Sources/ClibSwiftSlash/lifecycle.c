#include "lifecycle.h"
#include <stdatomic.h>
#include <pthread.h>

const size_t _so_pid = sizeof(pid_t);

void lc_init() {
	lifecyclestore_ptr_t newLC = malloc(sizeof(lifecyclestore_t));
	hashmap_create(16, &newLC->heapstore);
	atomic_store_explicit(&newLC->tlock, NULL, memory_order_release);
	lifecyclestore_global = newLC;
}

int lc_launch(terminationgroup_ptr_t tg) {
	void* pidptr = tg_pid_ptr(tg);
	
	// acquire the tlock for the hashmap
	pthread_ptr_t expectedPtr = NULL;
	const pthread_t tid = pthread_self();
	while (atomic_compare_exchange_weak_explicit(&lifecyclestore_global->tlock, &expectedPtr, &tid, memory_order_acq_rel, memory_order_relaxed) == false) {
		usleep(500);
		expectedPtr = NULL;
	}
	
	// store the tg in the hashmap
	int retval = hashmap_put(&lifecyclestore_global->heapstore, pidptr, _so_pid, tg);
	
	// release lock
	atomic_store_explicit(&lifecyclestore_global->tlock, NULL, memory_order_release);
	return retval;
}

int lc_exit(pid_t pid, int code) {
	// acquire the tlock for the hashmap
	pthread_ptr_t expectedPtr = NULL;
	const pthread_t tid = pthread_self();
	while (atomic_compare_exchange_strong_explicit(&lifecyclestore_global->tlock, &expectedPtr, &tid, memory_order_acq_rel, memory_order_relaxed) == false) {
		usleep(500);
		expectedPtr = NULL;
	}
	
	// retrieve the termination group from the hashmap
	terminationgroup_ptr_t tg = hashmap_get(&lifecyclestore_global->heapstore, (const char*)&pid, _so_pid);
	
	// remove the termination group from the hashmap
	int retval = hashmap_remove(&lifecyclestore_global->heapstore, (const char*)&pid, _so_pid);
	
	// release the tlock
	atomic_store_explicit(&lifecyclestore_global->tlock, NULL, memory_order_release);
	
	// mark the termination group as exited if it was removed from the hashmap successfully
	if (retval == 0) {
		retval += tg_exit(tg, code);
	}
	
	return retval;
}

int lc_signal(pid_t pid, int code) {
	// acquire the tlock for the hashmap
	pthread_ptr_t expectedPtr = NULL;
	const pthread_t tid = pthread_self();
	while (atomic_compare_exchange_strong_explicit(&lifecyclestore_global->tlock, &expectedPtr, &tid, memory_order_acq_rel, memory_order_relaxed) == false) {
		usleep(500);
		expectedPtr = NULL;
	}
	
	// retrieve the termination group from the hashmap
	terminationgroup_ptr_t tg = hashmap_get(&lifecyclestore_global->heapstore, (const char*)&pid, _so_pid);
	
	// remove the termination group from the hashmap
	int retval = hashmap_remove(&lifecyclestore_global->heapstore, (const char*)&pid, _so_pid);
	
	// release the tlock
	atomic_store_explicit(&lifecyclestore_global->tlock, NULL, memory_order_release);
	
	// mark the termination group as exited if it was removed from the hashmap successfully
	if (retval == 0) {
		retval += tg_signal(tg, code);
	}
	
	return retval;
}

void lc_dealloc() {
	hashmap_destroy(&lifecyclestore_global->heapstore);
	free(lifecyclestore_global);
}
