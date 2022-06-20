//
//  terminationgroup.h
//  
//
//  Created by Tanner Silva on 6/14/22.
//

#ifndef CLIBSWIFTSLASH_TG_H
#define CLIBSWIFTSLASH_TG_H

#include <stdio.h>
#include "libswiftslash.h"
#include <stdint.h>

// various states that a process can be in
typedef enum processstatus {
	launching = 1,
	running = 2,
	exited = 3,
	signaled = 4
} processstatus_t;

// termination handler: used by the termination group to notify when a process is done running
typedef void(*_Nonnull terminationhandler)(usr_ptr_t, pid_t, int);

/*
 termination group
 -----------------
 memory relationship: heap allocated structure
	-	no need for manual memory management
		-	termination group will automatically free itself from memory after the process has exited & all of its data channels have been closed & the termination handler has been fired.
 */
typedef struct terminationgroup {
	_Atomic uint8_t status;
	pid_t pid;
	int exitCode;
	uint count;
	usr_ptr_t usrPtr;
	terminationhandler th;
} terminationgroup_t;
typedef terminationgroup_t*_Nonnull terminationgroup_ptr_t;

terminationgroup_ptr_t tg_init(usr_ptr_t, terminationhandler);

// channel count management
int tg_increment(terminationgroup_ptr_t);
int tg_decrement(terminationgroup_ptr_t);

// lifecycle management
int tg_launch(terminationgroup_ptr_t, pid_t);
int tg_exit(terminationgroup_ptr_t, int);
int tg_signal(terminationgroup_ptr_t, int);

void*_Nullable tg_pid_ptr(terminationgroup_ptr_t);

int tg_dealloc(terminationgroup_ptr_t);

#endif /* CLIBSWIFTSLASH_TG_H */
