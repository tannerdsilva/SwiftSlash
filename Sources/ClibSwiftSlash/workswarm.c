//
//  workswarm.c
//  
//
//  Created by Tanner Silva on 7/2/22.
//

#include <stdio.h>
#include <unistd.h>
#include "workswarm.h"
#include <stdatomic.h>

# ifdef DEBUG
// debug variable to help detect when writerinfo objects may be leaked
_Atomic uint64_t wcl_leak = 0;
uint64_t _leakval_wcl() {
	return atomic_load_explicit(&wcl_leak, memory_order_acquire);
}
# endif

// recursive push function (internal)
void wcl_push_i(workchain_link_aptr_t *_Nonnull head, workchain_link_ptr_t newLink) {
	workchain_link_ptr_t expected = NULL;
	if (atomic_compare_exchange_strong_explicit(head, &expected, newLink, memory_order_acq_rel, memory_order_relaxed) == false) {
		wcl_push_i(&expected->next, newLink);
	}
}

// external (base) push function
void wcl_push(workchain_link_aptr_t *_Nonnull base, workchain_link_aptr_t *_Nonnull head, const usr_ptr_t usrPtr, const work_item_ptr_f work_func) {
	// define the new link in the heap
	const workchain_link_t newLink = {
		.usrPtr = usrPtr,
		.work_func = work_func,
		.next = NULL
	};
	workchain_link_ptr_t newLinkPtr = memcpy(malloc(sizeof(workchain_link_t)), &newLink, sizeof(workchain_link_t));
# ifdef DEBUG
	atomic_fetch_add_explicit(&wcl_leak, 1, memory_order_acq_rel);
# endif
	// assign the new base if it is NULL
	workchain_link_ptr_t expectedBase = NULL;
	if (atomic_compare_exchange_strong_explicit(base, &expectedBase, newLinkPtr, memory_order_acq_rel, memory_order_relaxed) == true) {
		// base assigned, so place it as the head too
		atomic_store_explicit(head, newLinkPtr, memory_order_release);
	} else {
		// base already assigned, so place this new link by recursively traversing the head pointer until we reach a NULL pointer
		wcl_push_i(head, newLinkPtr);
		
		// push to the head.
		atomic_store_explicit(head, newLinkPtr, memory_order_release);
	}
}

// external pop function
uint8_t wcl_pop(workchain_link_aptr_t *_Nonnull base, workchain_link_aptr_t *_Nonnull head, usr_ptr_t *_Nonnull usrPtr, work_item_ptr_f*_Nullable work_func) {
	// check if the base is NULL or if it actually points to something
	workchain_link_ptr_t expectedBase = atomic_load_explicit(base, memory_order_acquire);
	
	if (expectedBase != NULL) {
		workchain_link_ptr_t nextLink = atomic_load_explicit(&expectedBase->next, memory_order_acquire);
		while (atomic_compare_exchange_strong_explicit(base, &expectedBase, nextLink, memory_order_acq_rel, memory_order_relaxed) == false) {
			nextLink = atomic_load_explicit(&expectedBase->next, memory_order_acquire);
		}
		(*usrPtr) = expectedBase->usrPtr;
		(*work_func) = expectedBase->work_func;
		
		free(expectedBase);
# ifdef DEBUG
		atomic_fetch_sub_explicit(&wcl_leak, 1, memory_order_acq_rel);
# endif

		return 0;
	} else {
		(*usrPtr) = NULL;
		(*work_func) = NULL;
		return 1;
	}
}

// close a work chain link and potentially all the data that is within it
void wcl_close(workchain_link_aptr_t *_Nonnull base, workchain_link_aptr_t *_Nonnull head, close_handler_f ch) {
	usr_ptr_t foundPtr = NULL;
	while (wcl_pop(base, head, &foundPtr, NULL) == 0) {
		ch(foundPtr);
	}
}

// ===================================================================

// function that handles the locked mutex scenario for the pthread cancellation state
static void worker_cancel_cleanup(void *ptr) {
#ifdef DEBUG
	pthread_t tid = pthread_self();
	printf("[ %p ] \t - \t thread cancelled\n", tid);
#endif
	
	work_thread_t *worker = ptr;
	pthread_mutex_unlock(worker->mutex);
}

typedef enum worker_status {
	worker_status_dead = 0,
	worker_status_launching = 1,
	worker_status_running = 2,
	worker_status_joinme = 4
} worker_status_e;

// worker thread
void* workLoop(void *ptr) {
	// define the swarm object that was passed into this thread
	work_thread_t *worker = ptr;
	
	// install the cleanup handler that will handle the mutex if this thread is cancelled
	pthread_cleanup_push(worker_cancel_cleanup, &worker);

# ifdef DEBUG
	pthread_t tid = pthread_self();
	printf("[ %p ] \t - \t launched pthread\n", tid);
# endif
	
	usr_ptr_t stackPtr;
	while (true) {

		// acquires the next job or blocks until one becomes available
		work_item_ptr_f workerFunc;
		pthread_mutex_lock(worker->mutex);
		while (wcl_pop(worker->base, worker->head, &stackPtr, &workerFunc) != 0) {
			pthread_cond_wait(worker->condition, worker->mutex);
		}
		
# ifdef DEBUG
		printf("[ %p ] \t - \t work acquired\n", tid);
# endif
		
		// pop the work off the stack before releasing lock
		work_item_ptr_t workitem = stackPtr;
		pthread_mutex_unlock(worker->mutex);
		
		// execute work
		workitem->work(workitem->usrPtr);
		
# ifdef DEBUG
		printf("[ %p ] \t - \t - \t work done\n", tid);
# endif
	}
	
	pthread_cleanup_pop(0);
	pthread_exit(NULL);
	return NULL;
}

int ws_init(workswarm_ptr_t ws) {
	// make mutex
	if (pthread_mutex_init(&ws->mutex, NULL) != 0) {
		return 1;
	}
	
	// make condition
	if (pthread_cond_init(&ws->condition, NULL) != 0) {
		pthread_mutex_destroy(&ws->mutex);
		return 1;
	}
	
	// initialize the work stack
	atomic_store_explicit(&ws->base, NULL, memory_order_release);
	atomic_store_explicit(&ws->head, NULL, memory_order_release);
	
	atomic_store_explicit(&ws->worker_count, 0, memory_order_release);
	
	// initialize the workers buffer
	uint16_t i = 0;
	while (i < SS_TNUM_MAX) {
		ws->workers[i].mutex = &ws->mutex;
		ws->workers[i].condition = &ws->condition;
		ws->workers[i].base = &ws->base;
		ws->workers[i].head = &ws->head;
		ws->workers[i].status = worker_status_dead;
		ws->workers[i].worker = NULL;
		ws->workers[i].worker_count = &ws->worker_count;
		i += 1;
	}
	
	return 0;
}

int ws_close(workswarm_ptr_t ws) {
	int errval = 0;
	
	// lock the mutex so that the status of the threads can be evaluated and modified
	// the primary reason for acquiring this lock is to modify the state of all running threads to `dead` status
	pthread_mutex_lock(&ws->mutex);
	worker_count_type wc = atomic_load_explicit(&ws->worker_count, memory_order_acquire);
	
	// threads that need joining are stored here
	uint16_t joinI = 0;
	pthread_t joinThreads[SS_TNUM_MAX];
	
	// scan all the workers and evaluate their status
	//	-	running/launching threads will be cancelled and added to joinThreads for later joining
	//	-	threads that are 'joinme' will be added to the joinThreads for later joining
	uint16_t i = 0;
	while (i < SS_TNUM_MAX) {
		if (ws->workers[i].status == worker_status_running || ws->workers[i].status == worker_status_launching) {
			// workers of this status need cancellation
			joinThreads[joinI] = ws->workers[i].worker;
			errval += pthread_cancel(ws->workers[i].worker);
			ws->workers[i].status = worker_status_joinme;
			joinI += 1;
		} else if (ws->workers[i].status == worker_status_joinme) {
			// workers of this status simply need joining
			joinThreads[joinI] = ws->workers[i].worker;
			joinI += 1;
		}
		i += 1;
	}
	
	// status modifications done. unlock
	errval += pthread_mutex_unlock(&ws->mutex);
	
	// join the threads that have been closed
	i = 0;
	while (i < joinI) {
		errval = pthread_join(joinThreads[i], NULL);
	}
	
	// destroy the things that have been created now that all of the running threads have been closed and joinend
	errval += pthread_mutex_destroy(&ws->mutex);
	errval += pthread_cond_destroy(&ws->condition);
	return errval;
}

int ws_submit(workswarm_ptr_t ws, const usr_ptr_t usrPtr, const work_item_f work) {
	
}
