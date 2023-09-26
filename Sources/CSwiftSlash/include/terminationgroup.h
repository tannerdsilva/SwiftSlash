#ifndef CLIBSWIFTSLASH_TG_H
#define CLIBSWIFTSLASH_TG_H

#include <stdio.h>
#include <stdint.h>
#include <aio.h>

/// various states that a process can be in
typedef enum processstatus {
	tg_launching = 0,
	tg_running = 1,
	tg_exited = 2,
	tg_signaled = 3,
	tg_aborted = 4
} processstatus_t;

/// pid pointer type.
typedef pid_t*_Nullable pid_ptr_t;

/// termination handler: used by the termination group to notify when a process is done running.
typedef void(^_Nonnull tg_handler_f)(pid_t, processstatus_t, int);

/*
 termination group
 -----------------
 memory relationship: heap allocated structure
	-	no need for manual memory management
		-	termination group will automatically free itself from memory after the process has exited & all of its data channels have been closed & the termination handler has been fired.
	-	fully atomic, safe for concurrent and multithreaded use.
*/
typedef struct terminationgroup {
	/// the status of the process. see processstatus_t for more information on possible values.
	_Atomic uint8_t status;
	/// the pid of the running process.
	pid_t pid;
	/// the exit code of the process. only valid if the process has exited.
	_Atomic int exitCode;
	/// the number of data channels that are still open.
	_Atomic uint32_t count;
	/// the termination handler. called when the process has exited.
	const tg_handler_f th;
} terminationgroup_t;
typedef terminationgroup_t*_Nonnull terminationgroup_ptr_t;
typedef terminationgroup_t*_Nullable terminationgroup_optr_t;

/// @brief initialize a new termination group.
/// @return a pointer to a newly allocated termination group.
terminationgroup_ptr_t tg_init(const tg_handler_f);

// channel count management
/// @brief increment the channel count of a termination group.
int tg_increment(terminationgroup_ptr_t);
/// decrement the channel count of a termination group.
int tg_decrement(terminationgroup_ptr_t);

// lifecycle management
/// set the state of a termination group to running.
int tg_launch(terminationgroup_ptr_t, pid_t);
/// set the state of a termination group to exited.
int tg_exit(terminationgroup_ptr_t, int);
/// set the state of a termination group to signaled (failure).
int tg_signal(terminationgroup_ptr_t, int);
/// set the state of a termination group to aborted (failure).
int tg_abort(terminationgroup_ptr_t);

pid_ptr_t tg_pid_ptr(terminationgroup_ptr_t);

int tg_dealloc(terminationgroup_ptr_t);

#endif /* CLIBSWIFTSLASH_TG_H */
