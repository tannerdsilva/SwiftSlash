#include "libswiftslash.h"

#include <sys/resource.h>
#include <dirent.h>
#include <stdio.h>

pid_t cfork(void) {
	return fork();
}

int getfdlimit(double *utilized, double *limit) {
	struct rlimit rlim;
	int getlimresult = getrlimit(RLIMIT_NOFILE, &rlim);
	struct dirent *pDirent;
	
#ifdef __linux__
	DIR *pDir = opendir("/proc/self/fd");
#endif

#ifdef __APPLE__
	DIR *pDir = opendir("/dev/fd");
#endif

	switch(getlimresult) {
		case 0:
			if (pDir == NULL) {
				*utilized = -1;
				*limit = -1;
				return 5;
			}
			*limit = (double)rlim.rlim_cur;
			double totalDesc = 0;
			while ((pDirent = readdir(pDir)) != NULL) {
				if (pDirent->d_reclen > 0) {
					switch(pDirent->d_name[0]) {
						case 46:
							break;
						default:
							totalDesc = totalDesc + 1;
					}
				}
			}
			closedir(pDir);
			*utilized = totalDesc;
			return 0;
		default:
			*utilized = -1;
			*limit = -1;
			return getlimresult;
	}
}
