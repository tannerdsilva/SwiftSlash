#ifndef _CSWIFTSLASH_POSIX_HELPERS_H
#define _CSWIFTSLASH_POSIX_HELPERS_H

#include <errno.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>
#include <dirent.h>

/// @brief swift compiler will not allow for calling fork directly, so this function is a wrapper around the fork function.
/// @return the result of the fork function call.
pid_t _cswiftslash_fork();

/// @brief swift compiler will not allow for calling execvp directly, so this function is a wrapper around the execvp function.
/// @param file the file path to execute.
/// @param argv the arguments to pass to the executing file path.
int _cswiftslash_execvp(const char *file, char *const argv[]);

/// @brief swift compiler swift compilter cannot reference the errno macro, so this a function-style wrapper around the errno var macro.
/// @return the value of the errno variable.
int _cswiftslash_get_errno();

/// @brief swift cannot call variadic functions, so this function is a wrapper around the open function that does not take a mode argument.
/// @param path the path to open.
/// @param flags the flags to open the file with.
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