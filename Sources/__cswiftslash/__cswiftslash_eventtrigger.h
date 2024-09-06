// LICENSE MIT
// copyright (c) tanner silva 2024. all rights reserved.
#ifndef _CSWIFTSLASH_EVENTTRIGGER_H
#define _CSWIFTSLASH_EVENTTRIGGER_H

#include "__cswiftslash_types.h"

#ifdef __linux__
#include <sys/epoll.h>
#include <sys/ioctl.h>

/// @brief a wrapper function for `ioctl(fd, FIONREAD, &byteCount)`. swift cannot call into variadic functions, let alone passing some inout shit into a variable arg...so here we are with this function. only used on Linux.
/// @param fd the file descriptor associated with the fionread request.
/// @param sizeptr the resulting value of the fionread request.
/// @return 0 if the fionread request returns a value as expected. a non-zero value will be returned if an unexpected error is encountered.
int _cswiftslash_fcntl_fionread(int fd, int *_Nonnull sizeptr);

#endif

#endif // _CSWIFTSLASH_EVENTTRIGGER_H