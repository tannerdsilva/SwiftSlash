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

void __cswiftslash_ignore_sigpipe(void) {
	signal(SIGPIPE, SIG_IGN);
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

int __cswiftslash_create_launch_descriptor(int *read_out, int *write_out) {
	if (read_out == NULL || write_out == NULL) {
		return EINVAL;
	}
	int fds[2];
	if (pipe(fds) != 0) {
		return errno;
	}
	int read_fd = fds[0];
	int write_fd = fds[1];

	/* the read end must not already sit at the reserved number. `dup2(x, x)` is
	   a no-op that leaves close-on-exec set, so the child would silently lose the
	   descriptor and degrade to the default placement. when the reserved number
	   was free, the pipe can hand it back to us. */
	if (read_fd == __CSWIFTSLASH_LAUNCH_DESCRIPTOR_FD) {
		int moved = fcntl(read_fd, F_DUPFD, __CSWIFTSLASH_LAUNCH_DESCRIPTOR_FD + 1);
		if (moved < 0) {
			int saved = errno;
			close(read_fd);
			close(write_fd);
			return saved;
		}
		close(read_fd);
		read_fd = moved;
	}

	/* both ends close-on-exec: the only thing that lets the descriptor survive
	   into the child is the spawn file action that dup2s the read end onto the
	   reserved number, and dup2 clears close-on-exec on its target. */
	if (fcntl(read_fd, F_SETFD, FD_CLOEXEC) != 0 || fcntl(write_fd, F_SETFD, FD_CLOEXEC) != 0) {
		int saved = errno;
		close(read_fd);
		close(write_fd);
		return saved;
	}

	*read_out = read_fd;
	*write_out = write_fd;
	return 0;
}

int __cswiftslash_write_launch_descriptor(int write_fd, int placement) {
	__cswiftslash_launch_descriptor record;
	record.magic = __CSWIFTSLASH_LAUNCH_DESCRIPTOR_MAGIC;
	record.version = __CSWIFTSLASH_LAUNCH_DESCRIPTOR_VERSION;
	record.placement = (int32_t)placement;
	record.launcher_pid = (int32_t)getpid();
	record.launcher_pgid = (int32_t)getpgid(0);

	/* the record is 24 bytes and a pipe holds at least 4096, so this cannot
	   block, and the child therefore never has to wait for it. */
	ssize_t written = write(write_fd, &record, sizeof(record));
	if (written != (ssize_t)sizeof(record)) {
		return (written < 0) ? errno : EIO;
	}
	return 0;
}

int __cswiftslash_probe_launch_descriptor(__cswiftslash_launch_descriptor *out) {
	if (out == NULL) {
		return EINVAL;
	}
	/* NEVER read unless the reserved number is ready to be read.
	   a real descriptor has its record written before the spawn, so it is
	   readable immediately and this returns at once. anything ELSE sitting at
	   that number — a socket, a pipe whose writer is still alive, a terminal —
	   would BLOCK a bare read, and the launching process would hang at its
	   first launch with no diagnostic at all. a zero timeout turns this from a
	   wait into a question. */
	struct pollfd readiness;
	readiness.fd = __CSWIFTSLASH_LAUNCH_DESCRIPTOR_FD;
	readiness.events = POLLIN;
	readiness.revents = 0;
	int pollResult = poll(&readiness, 1, 0);
	if (pollResult < 0) {
		return errno;
	}
	if (pollResult == 0) {
		/* nothing to read: not inside a launch, or holding a descriptor that
		   carries nothing for us. */
		return ENOENT;
	}
	if ((readiness.revents & (POLLIN | POLLHUP)) == 0) {
		/* an invalid or errored descriptor: there is nothing to read, and
		   reading it is not a safe way to find that out. */
		return ENOENT;
	}
	__cswiftslash_launch_descriptor record;
	/* a single exact-size read, now known not to block. the record was written
	   before the spawn. the read CONSUMES it, which is why callers cache the
	   answer. */
	ssize_t got = read(__CSWIFTSLASH_LAUNCH_DESCRIPTOR_FD, &record, sizeof(record));
	if (got != (ssize_t)sizeof(record)) {
		return (got < 0) ? errno : ENOENT;
	}
	if (record.magic != __CSWIFTSLASH_LAUNCH_DESCRIPTOR_MAGIC) {
		return ENOENT;
	}
	if (record.version != __CSWIFTSLASH_LAUNCH_DESCRIPTOR_VERSION) {
		return ENOENT;
	}
	/* verifiable, not merely plausible: the placement the record names has to
	   agree with where this process actually sits. an inherited child is in the
	   launcher's group; every other placement makes the child its own leader. */
	pid_t expected_pgid = (record.placement == __cswiftslash_pgroup_mode_inherited)
		? (pid_t)record.launcher_pgid
		: getpid();
	if (getpgid(0) != expected_pgid) {
		return ENOENT;
	}
	*out = record;
	return 0;
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
///   - groupMode: one of `__cswiftslash_pgroup_mode`.
///   - launchDescriptorReadFD: the read end to install at the reserved number, or -1.
/// - Returns: 0 on success; an errno value on failure.
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

	/* install this launch's descriptor at the reserved number, LAST.
	   the order is load-bearing. file actions run in sequence in the child, and
	   the reserved number is very often the number of one of the CHANNEL ends
	   this very launch just created (a pipe takes the lowest free numbers, so a
	   freed 3 becomes a channel end). installing the descriptor first would
	   overwrite that end before the channel binding above had read it, and the
	   child's stdio would silently be wired to the descriptor instead of to the
	   caller's pipe. running last means every channel source has already been
	   consumed, and the descriptor then claims the reserved number for itself —
	   which is what "reserved" means: a caller binding a channel to that number
	   does not keep it.

	   dup2 onto the reserved number replaces and closes whatever the child
	   inherited there — the enclosing launch's descriptor — so exactly one
	   generation is ever visible, and it clears close-on-exec on the target so
	   the descriptor survives exec and is passed along by any intermediary that
	   knows nothing about swiftslash. */
	if (launchDescriptorReadFD >= 0) {
		r = posix_spawn_file_actions_adddup2(&actions, launchDescriptorReadFD, __CSWIFTSLASH_LAUNCH_DESCRIPTOR_FD);
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
	// place the child in the process-group hierarchy the caller asked for.
	//
	// own (the default): the child becomes the leader of its own process group
	// (pgid == its pid). this allows the parent to terminate the entire process
	// tree with a single kill(2) on the negated pid, which is the only way to
	// promptly shut down orchestration shells (e.g. `sh -c ...`) that defer
	// signals while waiting on a foreground child.
	//
	// inherited: the child joins the CALLER's process group. this is what a
	// nested launch must request so that an outer teardown's group signal
	// cascades into it - otherwise the nested child forms a second group that
	// the outer signal cannot reach, and its own descendants are reparented and
	// keep working after the outer caller has reported failure.
	//
	// detached: the child starts a new session. it outlives the launch and no
	// group signal can reach it; that is the point of asking for it. a session
	// leader is already a group leader, so POSIX_SPAWN_SETSID and
	// POSIX_SPAWN_SETPGROUP must not both be requested.
	short flags = POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF;
	switch (groupMode) {
		case __cswiftslash_pgroup_mode_inherited:
			r = posix_spawnattr_setpgroup(&attr, getpgid(0));
			if (r != 0) {
				posix_spawn_file_actions_destroy(&actions);
				posix_spawnattr_destroy(&attr);
				return r;
			}
			flags |= POSIX_SPAWN_SETPGROUP;
			break;
		case __cswiftslash_pgroup_mode_own:
			r = posix_spawnattr_setpgroup(&attr, 0);
			if (r != 0) {
				posix_spawn_file_actions_destroy(&actions);
				posix_spawnattr_destroy(&attr);
				return r;
			}
			flags |= POSIX_SPAWN_SETPGROUP;
			break;
		default: /* __cswiftslash_pgroup_mode_detached */
			flags |= POSIX_SPAWN_SETSID;
			break;
	}
	r = posix_spawnattr_setflags(&attr, flags);
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