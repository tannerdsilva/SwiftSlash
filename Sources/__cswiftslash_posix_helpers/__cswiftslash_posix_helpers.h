/*
LICENSE MIT
copyright (c) tanner silva 2024. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

#ifndef __CSWIFTSLASH_POSIX_HELPERS_H
#define __CSWIFTSLASH_POSIX_HELPERS_H

#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>
#include <dirent.h>

/// swift compiler will not allow for calling fork directly, so this function is a wrapper around the fork function.
/// @return the result of the fork function call.
pid_t __cswiftslash_fork();

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

#endif // __CSWIFTSLASH_POSIX_HELPERS_H