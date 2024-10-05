#include "__cswiftslash_posix_helpers.h"
#include <unistd.h>

pid_t _cswiftslash_fork() {
	return fork();
}

int _cswiftslash_execvp(const char *file, char *const argv[]) {
	return execvp(file, argv);
}

int _cswiftslash_get_errno() {
	return errno;
}

int _cswiftslash_open_nomode(const char *path, int flags) {
	return open(path, flags);
}

int _cswiftslash_fcntl_setfl(int fd, int flags) {
	return fcntl(fd, F_SETFL, flags);
}

int _cswiftslash_fcntl_setfd(int fd, int flags) {
	return fcntl(fd, F_SETFD, flags);
}

int _cswiftslash_fcntl_getfd(int fd) {
	return fcntl(fd, F_GETFD);
}