//
//  exittrigger.h.h
//  
//
//  Created by Tanner Silva on 6/15/22.
//

#ifndef CLIBSWIFTSLASH_LC_H
#define CLIBSWIFTSLASH_LC_H

#include <stdio.h>
#include "hashmap.h"
#include "terminationgroup.h"


/*
 lifecyclestore
 ----------
 memory relationship: heap allocated structure
 -	deallocate with `lc_close`
 -	this object is expected to have an exclusive allocation in memory for the entire duration of the process
 */
typedef struct lifecyclestore {
	_Atomic int sync;
	struct hashmap_s heapstore;
} lifecyclestore_t;
typedef lifecyclestore_t* lifecyclestore_ptr_t;


// initialize a new lifecyclestore in the heap
lifecyclestore_ptr_t lc_init();

// launch a new termination group
int lc_launch(lifecyclestore_ptr_t, terminationgroup_ptr_t);

// when a process exits
int lc_exit(lifecyclestore_ptr_t, pid_t, int);

// when a process fails with a signal
int lc_signal(lifecyclestore_ptr_t, pid_t, int);

// when the entire lifecyclestore is ready to be released from memory (should never be called under practical uses)
void lc_close(lifecyclestore_ptr_t);

#endif /* CLIBSWIFTSLASH_LC_H */
