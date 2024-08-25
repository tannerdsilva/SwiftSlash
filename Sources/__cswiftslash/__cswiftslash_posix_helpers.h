#ifndef _CSWIFTSLASH_ERRNO_HELPERS_H
#define _CSWIFTSLASH_ERRNO_HELPERS_H

#include <errno.h>
#include <sys/types.h>

pid_t _cswiftslash_fork();

int _cswiftslash_execvp(const char *file, char *const argv[]);

#endif // _CSWIFTSLASH_ERRNO_HELPERS_H