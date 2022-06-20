#ifndef CLIBSWIFTSLASH_H
#define CLIBSWIFTSLASH_H

#ifdef __linux__
#include <sys/epoll.h>
#endif

#include "lineparser.h"
#include <unistd.h>

typedef void*_Nullable usr_ptr_t;

pid_t cfork(void);
int getfdlimit(double*_Nonnull utilized, double*_Nonnull limit);

#endif
