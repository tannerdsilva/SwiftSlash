//
//  Header.h
//  
//
//  Created by Tanner Silva on 7/2/22.
//

#ifndef CLIBSWIFTSLASH_WS_H
#define CLIBSWIFTSLASH_WS_H

#include <pthread.h>
#include "hashmap.h"
#include "libswiftslash.h"

# ifdef DEBUG
uint64_t _leakval_wcl();
# endif

# ifndef SS_TNUM_MAX
# define SS_TNUM_MAX 64
# endif


// define a work item
typedef void(*_Nonnull work_item_f)(const usr_ptr_t);

// define a pointer to a work item
typedef work_item_f *_Nonnull work_item_ptr_f;

// free a work chain link from memory
typedef void(*_Nonnull close_handler_f)(const usr_ptr_t);


# ifdef DEBUG
typedef struct workchain_link {
	const usr_ptr_t usrPtr;
	const work_item_ptr_f work_func;
	_Atomic (struct workchain_link*_Nullable) next;
} workchain_link_t;

// these are chain links that are pushed and popped into the work swarm
typedef struct workchain_link*_Nullable workchain_link_ptr_t;
typedef _Atomic workchain_link_ptr_t workchain_link_aptr_t;

// push work into the swarm
void wcl_push(workchain_link_aptr_t *_Nonnull base, workchain_link_aptr_t *_Nonnull head, const usr_ptr_t usrPtr, const work_item_ptr_f work_func);

// remove work from the swarm
uint8_t wcl_pop(workchain_link_aptr_t *_Nonnull base, workchain_link_aptr_t *_Nonnull head, usr_ptr_t *_Nonnull usrPtr, work_item_ptr_f*_Nullable work_func);

void wcl_close(workchain_link_aptr_t *_Nonnull base, workchain_link_aptr_t *_Nonnull head, close_handler_f ch);
# endif

typedef _Atomic uint16_t worker_count_type;
typedef struct work_thread {
	// work stack
	workchain_link_aptr_t *_Nonnull base;
	workchain_link_aptr_t *_Nonnull head;
	pthread_mutex_t *_Nonnull mutex;
	pthread_cond_t *_Nonnull condition;
	
	worker_count_type *_Nonnull worker_count;

	// mutex protected values
	uint8_t status;
	pthread_t _Nullable worker;
} work_thread_t;

typedef struct workswarm {
	// pthread sync tools
	pthread_mutex_t mutex;
	pthread_cond_t condition;
	
	// work stack
	workchain_link_aptr_t base;
	workchain_link_aptr_t head;

	// workers
	worker_count_type worker_count; // what am I doing here, is this really needed?
	work_thread_t workers[SS_TNUM_MAX];
} workswarm_t;
typedef workswarm_t *_Nonnull workswarm_ptr_t;

int ws_init(workswarm_ptr_t ws);
int ws_close(workswarm_ptr_t ws);

int ws_submit(workswarm_ptr_t ws, const usr_ptr_t usrPtr, const work_item_f);
#endif /* CLIBSWIFTSLASH_ET_H */
