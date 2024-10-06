/*
LICENSE MIT
copyright (c) tanner silva 2024. all rights reserved.

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