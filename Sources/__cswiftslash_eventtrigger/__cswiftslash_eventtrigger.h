/*
LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

#ifndef __CSWIFTSLASH_EVENTTRIGGER_H
#define __CSWIFTSLASH_EVENTTRIGGER_H

#include <stdint.h>
#include <sys/wait.h>

#ifdef __linux__
#include <sys/epoll.h>
#include <sys/ioctl.h>
/// a wrapper function for `ioctl(fd, FIONREAD, &byteCount)`. swift cannot call into variadic functions, let alone passing some inout shit into a variable arg...so here we are with this function. only used on Linux.
/// @param fd the file descriptor associated with the fionread request.
/// @param sizeptr the resulting value of the fionread request.
/// @return 0 if the fionread request returns a value as expected. a non-zero value will be returned if an unexpected error is encountered.
int __cswiftslash_fcntl_fionread(int fd, int *_Nonnull sizeptr);
#endif // __linux__

#ifdef __APPLE__
#include <sys/types.h>
#include <sys/event.h>
#endif // __APPLE__

// c macros cannot be called from swift so wrapper functions must be declared.
/// wraps WIFSIGNALED as a discrete function instead of a macro.
int32_t __cswiftslash_eventtrigger_wifsignaled(const int32_t status);
/// wraps WIFEXITED as a discrete function instead of a macro.
int32_t __cswiftslash_eventtrigger_wifexited(const int32_t status);
/// wraps WTERMSIG as a discrete function instead of a macro.
int32_t __cswiftslash_eventtrigger_wtermsig(const int32_t status);
/// wraps WEXITSTATUS as a discrete function instead of a macro.
int32_t __cswiftslash_eventtrigger_wexitstatus(const int32_t status);

#endif // __CSWIFTSLASH_EVENTTRIGGER_H