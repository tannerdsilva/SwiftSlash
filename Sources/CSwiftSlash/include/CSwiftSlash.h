#ifndef CSWIFTSLASH_MASTER_H
#define CSWIFTSLASH_MASTER_H


#include <unistd.h>
#include <errno.h>
#include <sys/types.h>
#include <string.h>

#include "htable.h"
#include "lineparser.h"
#include "writerchain.h"
#include "terminationgroup.h"

#if __linux
#include <sys/epoll.h>
#endif

pid_t cfork(void);
int getErrno();

int getfdlimit(double*_Nonnull utilized, double*_Nonnull limit);

#endif