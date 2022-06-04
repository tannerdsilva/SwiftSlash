#ifndef CLIBSWIFTSLASH_ET_H
#define CLIBSWIFTSLASH_ET_H
#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>
#include <pthread.h>

enum handleevent {
	rclose,
	wclose,
	w,
	r
};

typedef struct eventtrigger {
	int pollqueue;
	
	pthread_t mainLoop;
	
	uint8_t *readBuffer;
	uint64_t bufferCap;
	
	uint64_t allocCap;
#if __APPLE__
	struct kevent* allocations;
#elif __linux
	struct epoll_event* allocations;
#endif

} eventtrigger;

typedef void(*writehandler)(int, bool);
typedef struct writerinfo {
	int fh;
	writehandler handler;
} writerinfo_t;

typedef void(*readhandler)(int, uint8_t*, size_t, bool);
typedef struct readerinfo {
	int fh;
	readhandler handler;
} readerinfo_t;

eventtrigger* et_alloc();
int et_init(eventtrigger *et);
int et_close(eventtrigger *et);

int et_w_register(const eventtrigger *et, const writerinfo_t *wi);
int et_r_register(const eventtrigger *et, const readerinfo_t *ri);
#endif
