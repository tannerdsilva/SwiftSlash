#ifndef CLIBSWIFTSLASH_MASTER_H
#define CLIBSWIFTSLASH_MASTER_H

#include <unistd.h>
#include <errno.h>
#include <sys/types.h>
#include "string.h"

#include "lineparser.h"
#include "terminationgroup.h"

typedef void*_Nullable usr_ptr_t;

pid_t cfork(void);
int getErrno();

int getfdlimit(double*_Nonnull utilized, double*_Nonnull limit);

#endif