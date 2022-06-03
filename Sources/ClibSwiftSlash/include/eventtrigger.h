#ifndef CLIBSWIFTSLASH_ET_H
#define CLIBSWIFTSLASH_ET_H
#include <stdio.h>
#include <stdbool.h>

enum handleevent {
	rclose,
	wclose,
	w,
	r
};

typedef struct eventtrigger {
	int pollqueue;
	pthread_t mainLoop;
	uint16_t allocCap;
#if __APPLE__
	struct kevent* allocations;
#elif __linux
	struct epoll_event* allocations;
#endif
} eventtrigger;

typedef void(*writehandler)(int, bool);
typedef void(*readhandler)(int, size_t, bool);

eventtrigger* et_alloc();
int et_init(eventtrigger *et);
int et_close(eventtrigger *et);

int et_w_register(eventtrigger *et, int fh, writehandler wh);
int et_r_register(eventtrigger *et, int fh, readhandler rh);

int et_w_deregister(eventtrigger *et, int fh);
int et_r_deregister(eventtrigger *et, int fh);

#endif
