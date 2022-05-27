#include <unistd.h>
#ifdef __linux__
#include <sys/epoll.h>
#endif

pid_t cfork(void);

int getfdlimit(double *utilized, double *limit);
