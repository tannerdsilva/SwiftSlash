#ifndef _CSWIFTSLASH_POSIX_HELPERS_H
#define _CSWIFTSLASH_POSIX_HELPERS_H

#include <errno.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>
#include <dirent.h>

pid_t _cswiftslash_fork();

int _cswiftslash_execvp(const char *file, char *const argv[]);

int _cswiftslash_get_errno();

int _cswiftslash_open_nomode(const char *path, int flags);

/// @brief swift cannot call variadic functions, so this function is a wrapper around the fcntl function that sets the flags.
/// @param fd the file descriptor to set the flags on.
/// @param flags the flags to set on the file descriptor.
/// @return the result of the fcntl function call.
int _cswiftslash_fcntl_setfl(int fd, int flags);


/// @brief swift cannot call variadic functions, so this function is a wrapper around the fcntl function that sets the flags.
/// @param fd the file descriptor to set the flags on.
/// @param flags the flags to set on the file descriptor.
/// @return the result of the fcntl function call.
int _cswiftslash_fcntl_setfd(int fd, int flags);


/// @brief swift cannot call variadic functions, so this function is a wrapper around the fcntl function that gets the flags.
/// @param fd the file descriptor to get the flags from.
/// @return the result of the fcntl function call.
int _cswiftslash_fcntl_getfd(int fd);

#endif // _CSWIFTSLASH_POSIX_HELPERS_H