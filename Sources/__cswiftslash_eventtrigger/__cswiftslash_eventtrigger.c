/*
LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

#include "__cswiftslash_eventtrigger.h"

#ifdef __linux__
int __cswiftslash_fcntl_fionread(int fd, int *_Nonnull sizeptr) {
	return ioctl(fd, FIONREAD, sizeptr);
}
#endif

int32_t __cswiftslash_eventtrigger_wifsignaled(const int32_t status) {
	return WIFSIGNALED(status);
}

int32_t __cswiftslash_eventtrigger_wifexited(const int32_t status) {
	return WIFEXITED(status);
}

int32_t __cswiftslash_eventtrigger_wtermsig(const int32_t status) {
	return WTERMSIG(status);
}

int32_t __cswiftslash_eventtrigger_wexitstatus(const int32_t status) {
	return WEXITSTATUS(status);
}

