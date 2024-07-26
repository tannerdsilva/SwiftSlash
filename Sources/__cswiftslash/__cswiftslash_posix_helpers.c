#include "__cswiftslash_posix_helpers.h"

pid_t _cswiftslash_fork() {
	return fork();
}

int _cswiftslash_execvp(const char *file, char *const argv[]) {
	return execvp(file, argv);
}