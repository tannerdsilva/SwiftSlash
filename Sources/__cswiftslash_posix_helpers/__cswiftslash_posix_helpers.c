/*
LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

#include "__cswiftslash_posix_helpers.h"
#include <unistd.h>
#include <errno.h>

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