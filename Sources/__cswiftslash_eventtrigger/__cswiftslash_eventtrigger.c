#include "__cswiftslash_eventtrigger.h"

int _cswiftslash_fcntl_fionread(int fd, int *_Nonnull sizeptr) {
	return ioctl(fd, FIONREAD, sizeptr);
}