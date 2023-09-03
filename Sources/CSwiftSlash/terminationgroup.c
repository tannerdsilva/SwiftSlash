#include "include/terminationgroup.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

terminationgroup_ptr_t tg_init(const tg_handler_f th) {
	terminationgroup_t newTG = {
		.status = tg_launching,
		.pid = 0,
		.exitCode = 0,
		.count = 0,
		.th = th
	};
	terminationgroup_ptr_t tgp = malloc(sizeof(terminationgroup_t));
	memcpy(tgp, &newTG, sizeof(terminationgroup_t));
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
	uint32_t oldCount = atomic_fetch_sub_explicit(&tg->count, 1, memory_order_acq_rel);
	uint8_t status = atomic_load_explicit(&tg->status, memory_order_acquire);
	switch (status) {
		// if the process is already done...
		case tg_exited:
		case tg_signaled:
		case tg_aborted:
			// ...and this is the last channel to close...
			if (oldCount == 1) {
				// ...get the exit code and fire the termination handler.
				int exitc = atomic_load_explicit(&tg->exitCode, memory_order_acquire);
				tg->th(tg->pid, status, exitc);
				return tg_dealloc(tg);
			}
			return 0;
		default:
			return 0;
	}
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
				tg->th(tg->pid, tg_exited, exitCode);
				return tg_dealloc(tg);
			}
			return 0;
		default:
			return 1;
	}
}

int tg_signal(terminationgroup_ptr_t tg, int signalCode) {
	switch (atomic_load_explicit(&tg->status, memory_order_acquire)) {
		case tg_running:
			atomic_store_explicit(&tg->status, tg_signaled, memory_order_release);
			atomic_store_explicit(&tg->exitCode, signalCode, memory_order_release);
			if (atomic_load_explicit(&tg->count, memory_order_acquire) == 0) {
				tg->th(tg->pid, tg_signaled, signalCode);
				return tg_dealloc(tg);
			}
			return 0;
		default:
			return 1;
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
		tg->th(0, tg_aborted, 0);
		return tg_dealloc(tg);
	}
	return 0;
}

pid_ptr_t tg_pid_ptr(terminationgroup_ptr_t tg) {
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