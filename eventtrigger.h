#ifndef CLIBSWIFTSLASH_ET_H
#define CLIBSWIFTSLASH_ET_H

#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>
#include <pthread.h>

#include "writerchain.h"
#include "lineparser.h"
#include "terminationgroup.h"
#include "htable.h"

# ifdef DEBUG
uint64_t _leakval_wi();
uint64_t _leakval_ri();
# endif

typedef void(^_Nonnull readpipeline)(const uint8_t*_Nonnull, const size_t, const bool);
typedef void(^_Nonnull writepipeline)(const bool);

// various states that a process can be in
typedef enum eventtriggerstate {
	ets_launching = 0,
	ets_looping = 1,
	ets_stopped = 2,
	ets_failed = 3
} eventtrigger_state_t;

struct readerinfo

/*
 event trigger
 ----------
 memory relationship: heap allocated object
 -	no deallocator - this object is designed to only have one instance that is initialized internally in the framework
 */
typedef const pthread_t _Nullable *_Nullable pthread_ptr_t;
typedef struct eventtrigger {
	struct htable enabledHandles;
	_Atomic pthread_ptr_t tlock;
	
	// pipeline handlers
	struct readpipeline rpipe;
	struct writepipeline wpipe;
	
	// primary pollqueue handle
	int pollqueue;
	
	// main thread (main event loop)
	_Nonnull pthread_t mainLoop;
	
	// main buffer that file handles are captured into
	uint8_t*_Nonnull readBuffer;
	uint64_t bufferCap;
	
	// event allocations buffer
	uint64_t allocCap;
#if __APPLE__
	struct kevent*_Nonnull allocations;
#elif __linux
	struct epoll_event*_Nonnull allocations;
#endif
} eventtrigger_t;
typedef eventtrigger_t*_Nonnull eventtrigger_ptr_t;

/*
 writer info
 ----------------
 memory relationship: heap allocated object
 -	external users of this structure need to call its corresponding `unhold` function when they no longer need the object in memory
 */
typedef struct writerinfo {
	_Atomic pthread_ptr_t tlock;
	eventtrigger_ptr_t et;
	terminationgroup_ptr_t tg;
	int fh;
	char fhStr[32];
	uint8_t fhStrLen;
	usr_ptr_t usrPtr;
	chaintail chain;
	bool isWritable;
	
	bool isOpen;
	bool isHeld;
} writerinfo_t;
typedef writerinfo_t*_Nonnull writerinfo_ptr_t;

writerinfo_ptr_t wi_init();
void wi_unhold(const writerinfo_ptr_t);
void wi_write(const writerinfo_ptr_t, const uint8_t*_Nullable, const size_t);
void wi_assign_tg(const writerinfo_ptr_t, const terminationgroup_ptr_t);

/* reader info
 memory relationship: heap allocated object
 -	external users of this structure need to call its corresponding `unhold` function when they no longer need the object in memory
*/
typedef struct readerinfo {
	_Atomic pthread_ptr_t tlock;
	eventtrigger_ptr_t et;
	terminationgroup_ptr_t tg;
	int fh;
	char fhStr[32];
	uint8_t fhStrLen;
	bool isOpen;
	bool isHeld;
} readerinfo_t;
typedef readerinfo_t*_Nonnull readerinfo_ptr_t;

readerinfo_ptr_t ri_init();
void ri_unhold(const readerinfo_ptr_t);
void ri_assign_tg(const readerinfo_ptr_t, const terminationgroup_ptr_t);
terminationgroup_ptr_t ri_retrieve_tg(const readerinfo_ptr_t);

// event trigger functions
eventtrigger_ptr_t et_alloc();
int et_init(eventtrigger_ptr_t, readpipeline rp, writepipeline wp);
int et_close(eventtrigger_ptr_t);

int et_w_register(const eventtrigger_ptr_t, const int fh, const usr_ptr_t userPointer, const writerinfo_ptr_t);
int et_r_register(const eventtrigger_ptr_t, const int fh, const uint8_t*_Nullable matchpat, const uint8_t matchpatlen, const usr_ptr_t userPointer, const readerinfo_ptr_t);

int et_w_deregister(const eventtrigger_ptr_t et, const int fh, const bool shouldLock);
int et_r_deregister(const eventtrigger_ptr_t et, const int fh, const bool shouldLock);

void memcmpTest();
#endif
