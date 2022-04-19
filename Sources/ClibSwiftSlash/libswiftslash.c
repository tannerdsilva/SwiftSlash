#include "libswiftslash.h"

#include <sys/resource.h>
#include <dirent.h>
#include <stdio.h>

pid_t cfork(void) {
	return fork();
}

//parses an individual index of the `environ` array
uint8_t __internal_environ_i_parse(char *buffer, char **name, size_t *name_len, char **value, size_t *value_len) {
	
	// mode 0: name
	// mode 1: value
	uint8_t mode = 0;
	
	//loop iterator
	size_t i = 0;
	
	//assign zero lengths to the pointers
	*name_len = 0;
	*value_len = 0;
	
	//parse the string to null termination
	while (buffer[i] != '\0') {
		if (buffer[i] == '=') {
			//name cannot have 0 length
			if (*name_len == 0) {
				return 1;
			}
			
			//initiate mode 1
			mode = 1;
			
			//assign the name buffer
			*name = buffer;
		}
		
		//mode determines if we are parsing through the name or value.
		switch (mode) {
			case 0:
				*name_len += 1;
			case 1:
				*value_len += 1;
			default:
				return 1;
		}
		
		//next character
		i += 1;
	}
	//pass back the starting buffer pointer for value
	if (*value_len == 0) {
		*value = buffer;
	}
	*value = &buffer[*name_len+2];
	return 0;
}

void parse_environ(void (*handler)(char*, size_t, char*, size_t)) {
//	environ
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
