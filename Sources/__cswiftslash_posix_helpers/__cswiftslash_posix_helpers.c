/*
LICENSE MIT
copyright (c) tanner silva 2026. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include "__cswiftslash_posix_helpers.h"
#include <unistd.h>
#include <errno.h>
#include <spawn.h>
#include <string.h>
#include <stddef.h>

pid_t __cswiftslash_fork() {
	return fork();
}

int __cswiftslash_execvp_safetycheck(const char *path) {
	struct stat sb;
	if (stat(path, &sb) < 0) {
		return -1;
	}
	if (!S_ISREG(sb.st_mode)) {
		errno = EACCES;
		return -1;
	}
	if (access(path, X_OK) < 0) {
		return -1;
	}
	return 0;
}

int __cswiftslash_execvp(const char *file, char *const argv[]) {
	return execvp(file, argv);
}

int __cswiftslash_get_errno() {
	return errno;
}

int __cswiftslash_open_nomode(const char *path, int flags) {
	return open(path, flags);
}

int __cswiftslash_fcntl_setfl(int fd, int flags) {
	return fcntl(fd, F_SETFL, flags);
}

int __cswiftslash_fcntl_setfd(int fd, int flags) {
	return fcntl(fd, F_SETFD, flags);
}

int __cswiftslash_fcntl_getfd(int fd) {
	return fcntl(fd, F_GETFD);
}

int __cswiftslash_fcntl_getfl(int fd) {
	return fcntl(fd, F_GETFL);
}

/// Cross-platform addchdir shim for spawn file actions.
/// - macOS >= 10.15: posix_spawn_file_actions_addchdir_np (deprecated in 26.0,
///   superseded by addchdir, but _np remains available and portable to .v15)
/// - glibc >= 2.29: posix_spawn_file_actions_addchdir_np (requires _GNU_SOURCE)
/// - musl: posix_spawn_file_actions_addchdir_np
static int cswiftslash_spawn_addchdir(posix_spawn_file_actions_t *actions, const char *wd) {
#if defined(__APPLE__) || defined(__GLIBC__) || defined(__linux__)
	return posix_spawn_file_actions_addchdir_np(actions, wd);
#else
	return posix_spawn_file_actions_addchdir(actions, wd);
#endif
}

/// Spawn a child process via posix_spawn, applying a set of dup2 file actions
/// and an optional chdir before exec. This is the fork-safety-correct
/// replacement for the old fork()/prepareLaunch() path: on macOS the kernel
/// applies the actions; on glibc/musl they run in a CLONE_VM|CLONE_VFORK child
/// doing only async-signal-safe work. The caller must mark every inherited fd
/// FD_CLOEXEC so nothing not named in `dup2Ops` survives into the child.
///
/// - Parameters:
///   - pid_out: receives the child pid on success.
///   - path: executable path.
///   - argv: null-terminated argv (argv[0] should be the program name).
///   - envp: null-terminated envp; pass NULL to inherit the parent environment.
///   - wd: working directory to chdir into before exec, or NULL to skip.
///   - dup2Ops: flat array of (srcfd, dstfd) pairs.
///   - dup2OpCount: number of pairs.
/// - Returns: 0 on success; an errno value on failure.
int __cswiftslash_posix_spawn(
	pid_t *pid_out,
	const char *path,
	char *const argv[],
	char *const envp[],
	const char *wd,
	const int *dup2Ops,
	size_t dup2OpCount
) {
	posix_spawn_file_actions_t actions;
	posix_spawnattr_t attr;
	int r = posix_spawn_file_actions_init(&actions);
	if (r != 0) {
		return r;
	}
	r = posix_spawnattr_init(&attr);
	if (r != 0) {
		posix_spawn_file_actions_destroy(&actions);
		return r;
	}

	for (size_t i = 0; i < dup2OpCount; i++) {
		int src = dup2Ops[i * 2];
		int dst = dup2Ops[i * 2 + 1];
		r = posix_spawn_file_actions_adddup2(&actions, src, dst);
		if (r != 0) {
			posix_spawn_file_actions_destroy(&actions);
			posix_spawnattr_destroy(&attr);
			return r;
		}
	}

	if (wd != NULL) {
		r = cswiftslash_spawn_addchdir(&actions, wd);
		if (r != 0) {
			posix_spawn_file_actions_destroy(&actions);
			posix_spawnattr_destroy(&attr);
			return r;
		}
	}

	// the child must begin with a pristine signal state: nothing blocked, and every
	// disposition at its default. the signal mask and ignored dispositions survive
	// exec, so without this a parent that blocks or ignores a signal (e.g. SIGTERM)
	// silently passes that state into the child, making kill(2) a no-op for the life
	// of the child.
	sigset_t sigmask;
	sigemptyset(&sigmask);
	r = posix_spawnattr_setsigmask(&attr, &sigmask);
	if (r != 0) {
		posix_spawn_file_actions_destroy(&actions);
		posix_spawnattr_destroy(&attr);
		return r;
	}
	sigset_t sigdefault;
	sigfillset(&sigdefault);
	r = posix_spawnattr_setsigdefault(&attr, &sigdefault);
	if (r != 0) {
		posix_spawn_file_actions_destroy(&actions);
		posix_spawnattr_destroy(&attr);
		return r;
	}
	// the child becomes the leader of its own process group (pgid == its pid). this
	// allows the parent to terminate the entire process tree with a single kill(2)
	// on the negated pid, which is the only way to promptly shut down orchestration
	// shells (e.g. sh -c ...) that defer signals while waiting on a foreground child.
	r = posix_spawnattr_setpgroup(&attr, 0);
	if (r != 0) {
		posix_spawn_file_actions_destroy(&actions);
		posix_spawnattr_destroy(&attr);
		return r;
	}
	r = posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETPGROUP);
	if (r != 0) {
		posix_spawn_file_actions_destroy(&actions);
		posix_spawnattr_destroy(&attr);
		return r;
	}

	pid_t pid = 0;
	r = posix_spawn(&pid, path, &actions, &attr, argv, envp);
	posix_spawn_file_actions_destroy(&actions);
	posix_spawnattr_destroy(&attr);
	if (r == 0 && pid_out != NULL) {
		*pid_out = pid;
	}
	return r;
}