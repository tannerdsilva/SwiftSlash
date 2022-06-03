#ifndef CLIBSWIFTSLASH_H
#define CLIBSWIFTSLASH_H

#ifdef __linux__
#include <sys/epoll.h>
#endif

#include "lineparser.h"
#include <unistd.h>

pid_t cfork(void);
int getfdlimit(double *utilized, double *limit);

#endif
