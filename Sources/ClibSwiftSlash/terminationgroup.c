//
//  terminationgroup.c
//  
//
//  Created by Tanner Silva on 6/14/22.
//

#include "terminationgroup.h"
#include <stdatomic.h>
#include <stdlib.h>

terminationgroup_ptr_t tg_init(usr_ptr_t usrPtr, terminationhandler th) {
	terminationgroup_ptr_t tgp = malloc(sizeof(terminationgroup_t));
	tgp->count = 0;
	tgp->th = th;
	tgp->usrPtr = usrPtr;
	atomic_store(&tgp->status, launching);
	return tgp;
}

int tg_increment(terminationgroup_ptr_t tg) {
	uint8_t status = atomic_load_explicit(&tg->status, memory_order_acquire);
	int retval;
	if (status == launching) {
		tg->count += 1;
		retval = 0;
	} else {
		retval = 1;
	}
	atomic_store_explicit(&tg->status, status, memory_order_release);
	return retval;
}

int tg_decrement(terminationgroup_ptr_t tg) {
	uint8_t status = atomic_load_explicit(&tg->status, memory_order_acquire);
	tg->count -= 1;
	
	// fire the termination handler if the count is 0 and the status is exited
	if (tg->count == 0 && ((status == exited) || (status == signaled))) {
		tg->th(tg->usrPtr, tg->pid, tg->exitCode);
	}
	atomic_store_explicit(&tg->status, status, memory_order_release);
	return 0;
}

int tg_launch(terminationgroup_ptr_t tg, pid_t newpid) {
	uint8_t status = atomic_load_explicit(&tg->status, memory_order_acquire);
	int retval;
	if (status == launching) {
		tg->pid = newpid;
		status = running;
		retval = 0;
	} else {
		retval = 1;
	}
	atomic_store_explicit(&tg->status, status, memory_order_release);
	return retval;
}

int tg_exit(terminationgroup_ptr_t tg, int exitCode) {
	uint8_t status = atomic_load_explicit(&tg->status, memory_order_acquire);
	int retval;
	if (status == running) {
		tg->exitCode = exitCode;
		status = exited;
		retval = 0;
		// fire the termination handler if the count is 0
		if (tg->count == 0) {
			tg->th(tg->usrPtr, tg->pid, exitCode);
			tg_dealloc(tg);
			return retval;
		}
	} else {
		retval = 1;
	}
	atomic_store_explicit(&tg->status, status, memory_order_release);
	return retval;
}

int tg_signal(terminationgroup_ptr_t tg, int signalCode) {
	uint8_t status = atomic_load_explicit(&tg->status, memory_order_acquire);
	int retval;
	if (status == running) {
		tg->exitCode = signalCode;
		status = signaled;
		retval = 0;
		// fire the termination handler if the count is 0
		if (tg->count == 0) {
			tg->th(tg->usrPtr, tg->pid, signalCode);
			tg_dealloc(tg);
			return retval;
		}
	} else {
		retval = 1;
	}
	atomic_store_explicit(&tg->status, status, memory_order_release);
	return retval;
}

void*_Nullable tg_pid_ptr(terminationgroup_ptr_t tg) {
	uint8_t status = atomic_load_explicit(&tg->status, memory_order_acquire);
	void* retval;
	if (status != launching) {
		retval = &tg->pid;
	} else {
		retval = NULL;
	}
	atomic_store_explicit(&tg->status, status, memory_order_release);
	return retval;
}

int tg_dealloc(terminationgroup_ptr_t tg) {
	free(tg);
	return 0;
}
