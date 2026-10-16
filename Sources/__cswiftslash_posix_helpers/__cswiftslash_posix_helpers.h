/*
LICENSE MIT
copyright (c) tanner silva 2026. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

#ifndef __CLIBSWIFTSLASH_POSIX_HELPERS_H
#define __CLIBSWIFTSLASH_POSIX_HELPERS_H

#include <poll.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>
#include <dirent.h>
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <errno.h>
#include <string.h>
#include <math.h>
#include <signal.h>

/// swift compiler will not allow for calling fork directly, so this function is a wrapper around the fork function.
/// @return the result of the fork function call.
pid_t __cswiftslash_fork();

/// check the specified path to ensure execvp will not fail if using it as an executable.
/// @param file the file path to check.
/// @return 0 if the file is a valid executable, -1 if it is not and errno is set.
int __cswiftslash_execvp_safetycheck(const char *path);

/// swift compiler will not allow for calling execvp directly, so this function is a wrapper around the execvp function.
/// @param file the file path to execute.
/// @param argv the arguments to pass to the executing file path.
int __cswiftslash_execvp(const char *file, char *const argv[]);

/// swift compiler swift compilter cannot reference the errno macro, so this a function-style wrapper around the errno var macro.
/// @return the value of the errno variable.
int __cswiftslash_get_errno();

/// swift cannot call variadic functions, so this function is a wrapper around the open function that does not take a mode argument.
/// @param path the path to open.
/// @param flags the flags to open the file with.
int __cswiftslash_open_nomode(const char *path, int flags);

/// swift cannot call variadic functions, so this function is a wrapper around the fcntl function that sets the flags.
/// @param fd the file descriptor to set the flags on.
/// @param flags the flags to set on the file descriptor.
/// @return the result of the fcntl function call.
int __cswiftslash_fcntl_setfl(int fd, int flags);

/// swift cannot call variadic functions, so this function is a wrapper around the fcntl function that sets the flags.
/// @param fd the file descriptor to set the flags on.
/// @param flags the flags to set on the file descriptor.
/// @return the result of the fcntl function call.
int __cswiftslash_fcntl_setfd(int fd, int flags);

/// swift cannot call variadic functions, so this function is a wrapper around the fcntl function that gets the flags.
/// @param fd the file descriptor to get the flags from.
/// @return the result of the fcntl function call.
int __cswiftslash_fcntl_getfd(int fd);

/// swift cannot call variadic functions, so this function is a wrapper around the fcntl function that gets the file status flags (F_GETFL).
/// @param fd the file descriptor to get the file status flags from.
/// @return the file status flags on success, or -1 with errno set.
int __cswiftslash_fcntl_getfl(int fd);

/// swift cannot portably reference the SIG_IGN macro, so this function is a
/// wrapper around signal(SIGPIPE, SIG_IGN). suppresses the terminating SIGPIPE
/// that a write to a pipe with no readers (a child that just exited) would
/// otherwise raise, so the write returns EPIPE and can be handled as an error.
void __cswiftslash_ignore_sigpipe(void);

/// where a spawned child sits in the process-group hierarchy. this decides which
/// signals reach the child and whether it outlives its launch, so it is part of
/// the spawn contract rather than a spawn detail.
typedef enum {
	__cswiftslash_pgroup_mode_own = 0,        /* child leads a new group (pgid == its pid) */
	__cswiftslash_pgroup_mode_inherited = 1,  /* child joins the caller's group */
	__cswiftslash_pgroup_mode_detached = 2    /* child starts a new session (setsid) */
} __cswiftslash_pgroup_mode;

/// the reserved descriptor number a launch installs its descriptor at. it is a
/// fixed number rather than an inherited variable so that placement is conveyed
/// by the process relationship itself, not by ambient configuration.
#define __CSWIFTSLASH_LAUNCH_DESCRIPTOR_FD 3

/// identifies a record as a swiftslash launch descriptor. "SW_SLASH_" in ascii
/// followed by the protocol byte.
#define __CSWIFTSLASH_LAUNCH_DESCRIPTOR_MAGIC 0x53575F534C415348ULL
/// the descriptor protocol version. a mismatch means the record is not ours.
#define __CSWIFTSLASH_LAUNCH_DESCRIPTOR_VERSION 1u

/// what a launch tells the child it is about to create. this is how a nested
/// launch learns that it is inside another launch without any consumer
/// cooperation and without environment variables.
typedef struct __attribute__((packed)) {
	uint64_t magic;         /* __CSWIFTSLASH_LAUNCH_DESCRIPTOR_MAGIC */
	uint32_t version;       /* __CSWIFTSLASH_LAUNCH_DESCRIPTOR_VERSION */
	int32_t  placement;     /* the __cswiftslash_pgroup_mode the launcher applied to this child */
	int32_t  launcher_pid;  /* the process that performed the spawn */
	int32_t  launcher_pgid; /* the launcher's process group at spawn time */
} __cswiftslash_launch_descriptor;

/// create the pipe a launch uses to describe itself to its child.
///
/// both ends are marked FD_CLOEXEC, so nothing survives into the child except
/// the read end that the spawn file actions dup2 onto the reserved number. the
/// read end is guaranteed not to already occupy that number: `dup2(x, x)` is a
/// no-op that does not clear close-on-exec, so the descriptor would silently
/// fail to reach the child.
/// @param read_out receives the read end, which the child will see at the reserved number.
/// @param write_out receives the write end, into which the record is written before the spawn.
/// @return 0 on success, or an errno value on failure.
int __cswiftslash_create_launch_descriptor(int *read_out, int *write_out);

/// write this process's launch record into a descriptor's write end. call it
/// BEFORE the spawn: the record is small enough that the write never blocks, and
/// the child can then read it without waiting.
/// @param write_fd the write end of a descriptor created by `__cswiftslash_create_launch_descriptor`.
/// @param placement the `__cswiftslash_pgroup_mode` being applied to the child.
/// @return 0 on success, or an errno value on failure.
int __cswiftslash_write_launch_descriptor(int write_fd, int placement);

/// probe the reserved descriptor for an enclosing launch's record.
///
/// the read consumes the record, which is why callers cache the answer: a
/// process's enclosing launch cannot change over its lifetime.
///
/// this NEVER blocks. a real record is written before the spawn, so it is
/// readable immediately; anything else sitting at that number — a socket, a
/// pipe whose writer is still alive, a terminal — is reported as "no
/// enclosing launch" rather than waited on. a bare read there would hang the
/// launching process at its first launch, with no diagnostic. the record is
/// VERIFIED rather than merely recognised — the placement it names has to agree
/// with where this process actually sits — so a coincidental magic match cannot
/// be mistaken for an enclosing launch.
/// @param out receives the record when this process was spawned by a launch.
/// @return 0 when a valid record was read, otherwise an errno value (ENOENT when
///         there is no usable record, including magic/version/placement mismatch).
int __cswiftslash_probe_launch_descriptor(__cswiftslash_launch_descriptor *out);

/// Spawn a child process via posix_spawn with dup2 file actions and optional chdir.
/// @param pid_out receives the child pid on success (may be NULL).
/// @param path the executable path.
/// @param argv null-terminated argument vector (argv[0] should be the program name).
/// @param envp null-terminated environment, or NULL to inherit the parent environment.
/// @param wd working directory to chdir into before exec, or NULL to skip.
/// @param dup2Ops flat array of (srcfd, dstfd) pairs.
/// @param dup2OpCount the number of (srcfd, dstfd) pairs.
/// @param groupMode one of `__cswiftslash_pgroup_mode`, deciding the child's process-group placement.
/// @param launchDescriptorReadFD the read end of this launch's descriptor, to be installed at the reserved number, or -1 for no descriptor.
/// @return 0 on success, or an errno value on failure.
int __cswiftslash_posix_spawn(
	pid_t *pid_out,
	const char *path,
	char *const argv[],
	char *const envp[],
	const char *wd,
	const int *dup2Ops,
	size_t dup2OpCount,
	int groupMode,
	int launchDescriptorReadFD
);

#endif // __CLIBSWIFTSLASH_POSIX_HELPERS_H