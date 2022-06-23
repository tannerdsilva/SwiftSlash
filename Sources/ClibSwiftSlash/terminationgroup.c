//
//  terminationgroup.c
//  
//
//  Created by Tanner Silva on 6/14/22.
//

#include "terminationgroup.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

terminationgroup_ptr_t tg_init(usr_ptr_t usrPtr, terminationhandler th) {
	terminationgroup_ptr_t tgp = malloc(sizeof(terminationgroup_t));
	tgp->th = th;
	atomic_store_explicit(&tgp->usrPtr, usrPtr, memory_order_release);
	atomic_store_explicit(&tgp->count, 0, memory_order_release);
	atomic_store_explicit(&tgp->status, tg_launching, memory_order_release);
	return tgp;
}

int tg_increment(terminationgroup_ptr_t tg) {
	switch (atomic_load_explicit(&tg->status, memory_order_acquire)) {
		case tg_launching:
			atomic_fetch_add_explicit(&tg->count, 1, memory_order_acq_rel);
			return 0;
		default:
			return 1;
	}
}

int tg_decrement(terminationgroup_ptr_t tg) {
	uint oldCount = atomic_fetch_sub_explicit(&tg->count, 1, memory_order_acq_rel);
	uint8_t status = atomic_load_explicit(&tg->status, memory_order_acquire);
	// fire the termination handler if the count is 0 and the status is exited
	if (oldCount == 1 && ((status == tg_exited) || (status == tg_signaled) || (status == tg_aborted))) {
		usr_ptr_t usrPtr = atomic_load_explicit(&tg->usrPtr, memory_order_acquire);
		int exitc = atomic_load_explicit(&tg->exitCode, memory_order_acquire);
		tg->th(usrPtr, tg->pid, status, exitc);
		tg_dealloc(tg);
	}
	return 0;
}

int tg_launch(terminationgroup_ptr_t tg, pid_t newpid) {
	switch (atomic_load_explicit(&tg->status, memory_order_acquire)) {
		case tg_launching:
			tg->pid = newpid;
			atomic_store_explicit(&tg->status, tg_running, memory_order_release);
			return 0;
		default:
			return 1;
	}
}

int tg_exit(terminationgroup_ptr_t tg, int exitCode) {
	switch (atomic_load_explicit(&tg->status, memory_order_acquire)) {
		case tg_running:
			atomic_store_explicit(&tg->status, tg_exited, memory_order_release);
			atomic_store_explicit(&tg->exitCode, exitCode, memory_order_release);
			if (atomic_load_explicit(&tg->count, memory_order_acquire) == 0) {
				usr_ptr_t usrPtr = atomic_load_explicit(&tg->usrPtr, memory_order_acquire);
				tg->th(usrPtr, tg->pid, tg_exited, exitCode);
				tg_dealloc(tg);
				return 0;
			}
			break;
		default:
			return 1;
			break;
	}
}

int tg_signal(terminationgroup_ptr_t tg, int signalCode) {
	switch (atomic_load_explicit(&tg->status, memory_order_acquire)) {
		case tg_running:
			atomic_store_explicit(&tg->status, tg_signaled, memory_order_release);
			atomic_store_explicit(&tg->exitCode, signalCode, memory_order_release);
			if (atomic_load_explicit(&tg->count, memory_order_acquire) == 0) {
				usr_ptr_t usrPtr = atomic_load_explicit(&tg->usrPtr, memory_order_acquire);
				tg->th(usrPtr, tg->pid, tg_signaled, signalCode);
				tg_dealloc(tg);
				return 0;
			}
			break;
		default:
			return 1;
			break;
	}
}

int tg_abort(terminationgroup_ptr_t tg) {
	uint8_t getStatus = atomic_load_explicit(&tg->status, memory_order_acquire);
	if ((getStatus == tg_launching) || (getStatus == tg_running)) {
		atomic_store_explicit(&tg->status, tg_aborted, memory_order_release);
	} else {
		return 1;
	}
	
	if (atomic_load_explicit(&tg->count, memory_order_acquire) == 0) {
		usr_ptr_t usrPtr = atomic_load_explicit(&tg->usrPtr, memory_order_acquire);
		tg->th(usrPtr, 0, tg_aborted, 0);
		tg_dealloc(tg);
	}
	return 0;
}

void*_Nullable tg_pid_ptr(terminationgroup_ptr_t tg) {
	uint8_t status = atomic_load_explicit(&tg->status, memory_order_acquire);
	if (status == tg_launching || status == tg_aborted) {
		return NULL;
	} else {
		return &tg->pid;
	}
}

int tg_dealloc(terminationgroup_ptr_t tg) {
	free(tg);
	return 0;
}
