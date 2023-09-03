#include "eventtrigger.h"
#include <sys/types.h>
#include <sys/time.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <errno.h>
#include <signal.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <limits.h>
#include <stdatomic.h>
#include <time.h>

#ifdef __linux__
#include <sys/epoll.h>
#elif __APPLE__
#include <sys/event.h>
#endif


# ifdef DEBUG
// debug variable to help detect when writerinfo objects may be leaked
_Atomic uint64_t wi_leak = 0;
uint64_t _leakval_wi() {
	return atomic_load_explicit(&wi_leak, memory_order_acquire);
}

// debug variable to help detect when readerinfo objects may be leaked
_Atomic uint64_t ri_leak = 0;
uint64_t _leakval_ri() {
	return atomic_load_explicit(&ri_leak, memory_order_acquire);
}

// function to help determine the number of microseconds between two timevals
//	-	`past` must be a date that is further back in time than the `further` variable
uint64_t useconds_elapsed(const struct timeval past, const struct timeval further) {
	return ((further.tv_sec - past.tv_sec) * 1000000) + (further.tv_usec - past.tv_usec);
}
# endif

// initialize writer info
writerinfo_ptr_t wi_init() {
	writerinfo_ptr_t pointer = malloc(sizeof(writerinfo_t));
	pointer->chain = NULL;
	pointer->fh = -1;
	pointer->isWritable = false;
	pointer->isOpen = false;
	pointer->isHeld = true;
	atomic_store_explicit(&pointer->tlock, NULL, memory_order_release);
# ifdef DEBUG
	atomic_fetch_add_explicit(&wi_leak, 1, memory_order_acq_rel);
# endif
	return pointer;
}
void wi_unhold(writerinfo_ptr_t info) {
	// acquire the tlock
	pthread_ptr_t expectedPtr = NULL;
	const pthread_t tid = pthread_self();
	while (atomic_compare_exchange_weak_explicit(&info->tlock, &expectedPtr, &tid, memory_order_acq_rel, memory_order_relaxed) == false) {
		usleep(500);
		expectedPtr = NULL;
	}
	// set held to false
	if (info->isHeld == true) {
		info->isHeld = false;
	}
	// if open is also false, then trelease the writerinfo struct from memory
	if (info->isOpen == false) {
		wc_close(&info->chain);
		free(info);
# ifdef DEBUG
		atomic_fetch_sub_explicit(&wi_leak, 1, memory_order_acq_rel);
# endif
		return;
	}
	// release the tlock
	atomic_store_explicit(&info->tlock, NULL, memory_order_release);
}
void wi_close(writerinfo_ptr_t info) {
	// acquire the tlock
	pthread_ptr_t expectedPtr = NULL;
	const pthread_t tid = pthread_self();
	while (atomic_compare_exchange_weak_explicit(&info->tlock, &expectedPtr, &tid, memory_order_acq_rel, memory_order_relaxed) == false) {
		usleep(500);
		expectedPtr = NULL;
	}
	// set writable to false
	if (info->isWritable == true) {
		info->isWritable = false;
	}
	// set open to false
	if (info->isOpen == true) {
		info->isOpen = false;
	}
	// if held is also false, then release the writerinfo struct from memory
	if (info->isHeld == false) {
		wc_close(&info->chain);
		free(info);
# ifdef DEBUG
		atomic_fetch_sub_explicit(&wi_leak, 1, memory_order_acq_rel);
# endif
		return;
	}
	// release the tlock
	atomic_store_explicit(&info->tlock, NULL, memory_order_release);
}
void wi_open(const writerinfo_ptr_t info, const int fh, const eventtrigger_ptr_t et, const usr_ptr_t usrPtr) {
	// acquire lock
	pthread_ptr_t expectedPtr = NULL;
	const pthread_t tid = pthread_self();
	while(atomic_compare_exchange_weak_explicit(&info->tlock, &expectedPtr, &tid, memory_order_acq_rel, memory_order_relaxed) == false) {
		usleep(500);
		expectedPtr = NULL;
	}
	
	// assign values
	info->fh = fh;
	info->fhStrLen = sprintf(info->fhStr, "%i", fh);
	info->usrPtr = usrPtr;
	info->isOpen = true;
	info->et = et;
	
	// release lock
	atomic_store_explicit(&info->tlock, NULL, memory_order_release);
}
void wi_setWritable(writerinfo_ptr_t info) {
	//acquire lock
	pthread_ptr_t expectedPtr = NULL;
	const pthread_t tid = pthread_self();
	while (atomic_compare_exchange_weak_explicit(&info->tlock, &expectedPtr, &tid, memory_order_acq_rel, memory_order_relaxed) == false) {
		usleep(500);
		expectedPtr = NULL;
	}
	
	int err;
	if (info->isOpen == true) {
		wc_flush(&info->chain, info->fh, &err);
		switch (err) {
			case 0:
				info->isWritable = true;
			default:
				info->isWritable = false;
		}
	}
	
	// release lock
	atomic_store_explicit(&info->tlock, NULL, memory_order_release);
}
void wi_write(writerinfo_ptr_t info, const uint8_t *buff, const size_t bufflen) {
	// acquire lock
	pthread_ptr_t expectedPtr = NULL;
	const pthread_t tid = pthread_self();
	while (atomic_compare_exchange_weak_explicit(&info->tlock, &expectedPtr, &tid, memory_order_acq_rel, memory_order_relaxed) == false) {
		usleep(500);
		expectedPtr = NULL;
	}
	
	// append the data to the buffer
	wc_append(&info->chain, buff, bufflen);
	
	// if the handle is writable, flush the buffer
	if (info->isWritable == true) {
		int err;
		wc_flush(&info->chain, info->fh, &err);
		if (err != 0) {
			info->isWritable = false;
		}
	}
	
	// release lock
	atomic_store_explicit(&info->tlock, NULL, memory_order_release);
}
void* wi_fhPtr(const writerinfo_ptr_t info) {
	return &info->fh;
}
void wi_assign_tg(const writerinfo_ptr_t info, const terminationgroup_ptr_t tg) {
	info->tg = tg;
}

readerinfo_ptr_t ri_init() {
	readerinfo_ptr_t pointer = malloc(sizeof(readerinfo_t));
	pointer->fh = -1;
	pointer->isOpen = false;
	pointer->isHeld = true;
	pointer->usrPtr = NULL;
	atomic_store_explicit(&pointer->tlock, NULL, memory_order_release);
# ifdef DEBUG
	atomic_fetch_add_explicit(&ri_leak, 1, memory_order_acq_rel);
# endif
	return pointer;
}
void ri_close(const readerinfo_ptr_t info) {
	pthread_ptr_t expectedPtr = NULL;
	// acquire a tlock
	const pthread_t tid = pthread_self();
	while (atomic_compare_exchange_weak_explicit(&info->tlock, &expectedPtr, &tid, memory_order_acq_rel, memory_order_relaxed) == false) {
		usleep(500);
		expectedPtr = NULL;
	}
	if (info->isOpen == true) {
		info->isOpen = false;
	}
	
	// release lock if this ri is not getting free'd from memory
	if (info->isHeld == false) {
# ifdef DEBUG
		atomic_fetch_sub_explicit(&ri_leak, 1, memory_order_acq_rel);
# endif
		free(info);
	} else {
		atomic_store_explicit(&info->tlock, NULL, memory_order_release);
	}
}
void ri_unhold(const readerinfo_ptr_t info) {
	pthread_ptr_t expectedPtr = NULL;
	// acquire a tlock
	const pthread_t tid = pthread_self();
	while (atomic_compare_exchange_weak_explicit(&info->tlock, &expectedPtr, &tid, memory_order_acq_rel, memory_order_relaxed) == false) {
		usleep(500);
		expectedPtr = NULL;
	}
	if (info->isHeld == true) {
		info->isHeld = false;
	}
	if (info->isOpen == false) {
# ifdef DEBUG
		atomic_fetch_sub_explicit(&ri_leak, 1, memory_order_acq_rel);
# endif
		free(info);
	} else {
		atomic_store_explicit(&info->tlock, NULL, memory_order_release);
	}
}
void ri_open(const readerinfo_ptr_t ri, const int fh, const eventtrigger_ptr_t et, const uint8_t*_Nullable matchpat, const uint8_t matchpatlen, const usr_ptr_t usrPtr) {
	// acquire lock
	pthread_ptr_t expectedPtr = NULL;
	const pthread_t tid = pthread_self();
	while(atomic_compare_exchange_weak_explicit(&ri->tlock, &expectedPtr, &tid, memory_order_acq_rel, memory_order_relaxed) == false) {
		usleep(500);
		expectedPtr = NULL;
	}
	ri->fhStrLen = sprintf(ri->fhStr, "%i", fh);
	ri->fh = fh;
	ri->isOpen = true;
	ri->et = et;
	ri->lp = lp_init(matchpat, matchpatlen);
	ri->usrPtr = usrPtr;
	atomic_store_explicit(&ri->tlock, NULL, memory_order_release);
}
void ri_assign_tg(const readerinfo_ptr_t ri, const terminationgroup_ptr_t tg) {
	ri->tg = tg;
}
void* ri_fhPtr(const readerinfo_ptr_t ri) {
	return &ri->fh;
}

void lphandler(const uint8_t*_Nonnull inbuff, const size_t bufflen, usr_ptr_t usrPtr) {
	((readerinfo_ptr_t)usrPtr)->et->rpipe(inbuff, bufflen, false, ((readerinfo_ptr_t)usrPtr)->usrPtr);
}

int et_w_deregister(const eventtrigger_ptr_t et, const int fh, const bool shouldLock) {

	if (shouldLock == true) {
		pthread_ptr_t expectedPtr = NULL;
		// acquire a tlock
		const pthread_t tid = pthread_self();
		while (atomic_compare_exchange_weak_explicit(&et->tlock, &expectedPtr, &tid, memory_order_acq_rel, memory_order_relaxed) == false && (*expectedPtr) != tid) {
			usleep(500);
			expectedPtr = NULL;
		}
	}
	
	char fhStr[24];
	int size = sprintf(fhStr, "%i", fh);
	writerinfo_ptr_t wi = hashmap_get(&et->enabledHandles, fhStr, size);
	
	if (wi != NULL) {
		// remove the writerinfo from the hashmap
		if (hashmap_remove(&et->enabledHandles, fhStr, size) != 0) {
			if (shouldLock == true) {
				atomic_store_explicit(&et->tlock, NULL, memory_order_release);
			}
			return 1;
		}
		
		// decrement the active count on the termination group
		if (tg_decrement(wi->tg) != 0) {
			hashmap_put(&et->enabledHandles, fhStr, size, wi);
			if (shouldLock == true) {
				atomic_store_explicit(&et->tlock, NULL, memory_order_release);
			}
			return 1;
		}
		
		// platform specific implementations
	#ifdef __linux__
		struct epoll_event regEvent;
		regEvent.data.fh = fh;
		regEvent.events = EPOLLOUT | EPOLLERR | EPOLLHUP | EPOLLET;
		int registerResult = epoll_ctl(et->pollqueue, EPOLL_CTL_DEL, fh, &regEvent);
	#elif __APPLE__
		struct kevent newEvent;
		newEvent.ident = fh;
		newEvent.flags = EV_DELETE | EV_CLEAR | EV_EOF;
		newEvent.filter = EVFILT_WRITE;
		newEvent.fflags = 0;
		newEvent.data = 0;
		newEvent.udata = NULL;
		int deregisterResult = kevent(et->pollqueue, &newEvent, 1, NULL, 0, NULL);
	#endif
		
		// handle the potential scenario where the registration failed
		if (deregisterResult != 0) {
			hashmap_put(&et->enabledHandles, fhStr, size, wi);
			tg_increment(wi->tg);
			if (shouldLock == true) {
				atomic_store_explicit(&et->tlock, NULL, memory_order_release);
			}
			return errno;
		}
		
		// mark the writerinfo as closed
		wi_close(wi);
		if (shouldLock == true) {
			atomic_store_explicit(&et->tlock, NULL, memory_order_release);
		}
		return 0;
	} else {
		// no writerinfo found in hashmap, return
		if (shouldLock == true) {
			atomic_store_explicit(&et->tlock, NULL, memory_order_release);
		}
		return 1;
	}
}

int et_r_deregister(const eventtrigger_ptr_t et, const int fh, const bool shouldLock) {
	if (shouldLock == true) {
		pthread_ptr_t expectedPtr = NULL;
		// acquire a tlock
		const pthread_t tid = pthread_self();
		while (atomic_compare_exchange_weak_explicit(&et->tlock, &expectedPtr, &tid, memory_order_acq_rel, memory_order_relaxed) == false && (*expectedPtr) != tid) {
			usleep(500);
			expectedPtr = NULL;
		}
	}
	
	char fhStr[24];
	int size = sprintf(fhStr, "%i", fh);
	readerinfo_ptr_t ri = hashmap_get(&et->enabledHandles, fhStr, size);
	
	if (ri != NULL) {
		// remove the readerinfo from the hashmap
		if (hashmap_remove(&et->enabledHandles, fhStr, size) != 0) {
			if (shouldLock == true) {
				atomic_store_explicit(&et->tlock, NULL, memory_order_release);
			}
			return 1;
		}
		
		// decrement the active count on the termination group
		if (tg_decrement(ri->tg) != 0) {
			hashmap_put(&et->enabledHandles, fhStr, size, ri);
			if (shouldLock == true) {
				atomic_store_explicit(&et->tlock, NULL, memory_order_release);
			}
			return 1;
		}
		
		// platform specific implementations
#ifdef __linux__
		struct epoll_event regEvent;
		regEvent.data.fh = fh;
		regEvent.events = EPOLLIN | EPOLLERR | EPOLLHUP | EPOLLET;
		int deregisterResult = epoll_ctl(et->pollqueue, EPOLL_CTL_DEL, fh, &regEvent);
#elif __APPLE__
		struct kevent newEvent;
		newEvent.ident = fh;
		newEvent.flags = EV_DELETE | EV_CLEAR | EV_EOF;
		newEvent.filter = EVFILT_READ;
		newEvent.fflags = 0;
		newEvent.data = 0;
		newEvent.udata = NULL;
		int deregisterResult = kevent(et->pollqueue, &newEvent, 1, NULL, 0, NULL);
#endif
		
		// handle the potential scenario where the registration failed
		if (deregisterResult != 0) {
			hashmap_put(&et->enabledHandles, fhStr, size, ri);
			tg_increment(ri->tg);
			if (shouldLock == true) {
				atomic_store_explicit(&et->tlock, NULL, memory_order_release);
			}
			return errno;
		}
		
		ri_close(ri);
		
		if (shouldLock == true) {
			atomic_store_explicit(&et->tlock, NULL, memory_order_release);
		}
		return 0;
		
	} else {
		// no readerinfo found in hashmap, return
		if (shouldLock == true) {
			atomic_store_explicit(&et->tlock, NULL, memory_order_release);
		}
		return 1;
	}
}

void et_validate_readsize(eventtrigger_ptr_t et, size_t readsize) {
	while (readsize > et->bufferCap) {
		et->bufferCap = et->bufferCap * 2;
		void* oldbuff = et->readBuffer;
		et->readBuffer = malloc(et->bufferCap);
		free(oldbuff);
	}
}

// writing available
void _wAvail(writerinfo_ptr_t ptr) {
	ptr->et->wpipe(false, ptr->usrPtr);
	wi_setWritable(ptr);
}

// reading available
uint64_t _rAvail(readerinfo_ptr_t ptr, const size_t rsize) {
	// resize the read buffer
	et_validate_readsize(ptr->et, rsize);
	
	// read the data
	int readresult;
	do {
		readresult = read(ptr->fh, ptr->et->readBuffer, rsize);
	} while ((readresult < 0) && (errno == EAGAIN || errno == EINTR));
	
	struct timeval startparse;
	gettimeofday(&startparse, NULL);
	
	// feed the newly captured data into the line parser
	if (readresult >= 0) {
		lp_intake(&ptr->lp, ptr->et->readBuffer, readresult, ptr, lphandler);
	} else {
		printf("READ RESULT ERROR %i\n", errno);
	}
	
	struct timeval endparse;
	gettimeofday(&endparse, NULL);
	
	uint64_t elapsed = useconds_elapsed(startparse, endparse);
	return elapsed;
}

// writing closed
void _wClose(writerinfo_ptr_t ptr) {
	// deregister the fh from the pollqueue
	int fhCapture = ptr->fh;
	int deregisterResult;
	do {
		deregisterResult = et_w_deregister(ptr->et, ptr->fh, false);
	} while (deregisterResult == EINTR);
	
	// fire the writer pipeline
	ptr->et->wpipe(true, ptr->usrPtr);
	
	// close the file handler
	int closeResult;
	do {
		closeResult = close(fhCapture);
	} while (closeResult == EINTR);
	if (closeResult < 0) {
		printf("CLOSE FAILED\n");
	}
}

void _rClose(readerinfo_ptr_t ptr, const size_t rsize) {
	// resize the read buffer
	et_validate_readsize(ptr->et, rsize);
	
	// read the data
	size_t readresult;
	do {
		readresult = read(ptr->fh, ptr->et->readBuffer, rsize);
	} while ((readresult < 0) && (errno == EAGAIN || errno == EINTR));
	
	// handle the data that was just read
	if (readresult > 0) {
		lp_intake(&ptr->lp, ptr->et->readBuffer, readresult, ptr, lphandler);
	} else if (readresult != 0) {
		printf("READ RESULT ERROR\n");
	}
	
	// close the line parser
	lp_close(&ptr->lp, ptr, lphandler);
	
	// capture the user pointer, call the reader pipeline with the closed flag
	ptr->et->rpipe(ptr->et->readBuffer, readresult, true, ptr->usrPtr);

	// deregister the file handle
	int fhCap = ptr->fh;
	int deregisterResult;
	do {
		deregisterResult = et_r_deregister(ptr->et, fhCap, false);
	} while (deregisterResult == EINTR);
	
	// close the file handle
	int closeResult;
	do {
		closeResult = close(fhCap);
	} while (closeResult == EINTR);
	if (closeResult < 0) {
		printf("CLOSE RESULT ERROR\n");
	}
}

void* mainLoop(void *argc) {
	eventtrigger_ptr_t et = ((eventtrigger_ptr_t)argc);
	
	// lock related variables
	pthread_ptr_t expectedPtr = NULL;
	const pthread_t tid = pthread_self();

	const size_t _so_int = sizeof(int);
	while (1) {
		int i = 0;
		pthread_testcancel();
		
//		printf("[ET] \t - \t WAITING FOR EVENTS...\n");
		struct timeval startWait;
		gettimeofday(&startWait, NULL);
#ifdef __linux__
		const int result = epoll_wait(et->pollqueue, et->allocations, et->allocCap, -1);
#elif __APPLE__
		const int result = kevent(et->pollqueue, NULL, 0, et->allocations, et->allocCap, NULL);
#endif
		struct timeval endWait;
		gettimeofday(&endWait, NULL);
		uint64_t elapsed = useconds_elapsed(startWait, endWait);
//		printf("[ET] \t - \t - \t DONE. WAITED FOR %llu microseconds.\n", elapsed);
		uint8_t state;
		int ii = 0;
		switch (result) {
			case -1:
				switch (errno) {
				case EINTR:
					printf("ERROR EINTR\n");
					break;
				case EBADF:
					printf("ERROR EBADF\n");
					break;
				case EFAULT:
					printf("ERROR EFAULT\n");
					break;
				case EINVAL:
					printf("ERRNO EINVAL\n");
					break;
				default:
					printf("ERRNO \(errno)\n");
					break;
				}
				break;
			default:
				// acquire a lock
				while (atomic_compare_exchange_strong_explicit(&et->tlock, &expectedPtr, &tid, memory_order_acq_rel, memory_order_relaxed) == false) {
					usleep(10);
					expectedPtr = NULL;
					ii += 1;
				}
				struct timeval lockgettime;
				gettimeofday(&lockgettime, NULL);
				elapsed = useconds_elapsed(endWait, lockgettime);
				
//				printf("[ET] \t - \t - \t LOCK ACQUIRED WITH %i ITERATIONS IN %llu MICROSECONDS.\n", ii, elapsed);
				char fhBuff[32];
				uint64_t totalParsingTime = 0;
#ifdef __linux__
				while (i < result) {
					uint8_t strSize = sprintf(fhBuff, "%lu", et->allocations[i].data.fh);
					if (et->allocations[i].events & EPOLLHUP) {
						//reading closed
						
						//determine how many bytes can be read
						size_t readableSize = 0;
						if (ioctl(((readerinfo_ptr_t)(et->allocations[i].data.ptr))->fh, FIONREAD, &readableSize) != 0) {
							printf("ioctl error %i", ((readerinfo_ptr_t)(et->allocations[i].data.ptr))->fh);
						} else {
							_rClose(et->allocations[i].data.ptr, readableSize);
						}
					} else if (et->allocations[i].events & EPOLLERR) {
						// writing closed
						_wClose(et->allocations[i].data.ptr);
					} else if (et->allocations[i].events & EPOLLIN) {
						//reading available
						
						//determine how many bytes can be read
						size_t readableSize = 0;
						if (ioctl(((readerinfo_ptr_t)(et->allocations[i].data.ptr))->fh, FIONREAD, &readableSize) != 0) {
							printf("ioctl error %i", ((readerinfo_ptr_t)(et->allocations[i].data.ptr))->fh);
						} else {
							_rAvail(et->allocations[i].data.ptr, readableSize);
						}
					} else if (et->allocations[i].events & EPOLLOUT) {
						//writing available
						_wAvail(et->allocations[i].data.ptr);
					}
					i = i + 1;
				}

#elif __APPLE__
				while (i < result) {
					uint8_t strSize = sprintf(fhBuff, "%lu", et->allocations[i].ident);
					if ((et->allocations[i].flags & EV_EOF) == 0) {
						if (et->allocations[i].filter == EVFILT_READ) {
							// reading available
							readerinfo_ptr_t rip = hashmap_get(&et->enabledHandles, fhBuff, strSize);
							if (rip != NULL) {
								totalParsingTime += _rAvail(rip, et->allocations[i].data);
							}
						} else if (et->allocations[i].filter == EVFILT_WRITE) {
							// writing available
							writerinfo_ptr_t wip = hashmap_get(&et->enabledHandles, fhBuff, strSize);
							if (wip != NULL) {
								_wAvail(wip);
							}
						}
					} else {
						if (et->allocations[i].filter == EVFILT_READ) {
							// reading closed
							readerinfo_ptr_t rip = hashmap_get(&et->enabledHandles, fhBuff, strSize);
							if (rip != NULL) {
								_rClose(rip, et->allocations[i].data);
							}
						} else if (et->allocations[i].filter == EVFILT_WRITE) {
							writerinfo_ptr_t wip = hashmap_get(&et->enabledHandles, fhBuff, strSize);
							if (wip != NULL) {
								// writing closed
								_wClose(wip);
							}
						}
					}
					i = i + 1;
				}
#endif
				
				struct timeval loopend;
				gettimeofday(&loopend, NULL);
				elapsed = useconds_elapsed(lockgettime, loopend);
				
				printf("[ET] \t - \t - \t - \t LOOP COMPLETED %llu / %llu\n", totalParsingTime, elapsed);
				atomic_store_explicit(&et->tlock, NULL, memory_order_release);
				
				if ((i * 2) > et->allocCap) {
					void* freePTR = et->allocations;
					et->allocCap = et->allocCap * 2;
#ifdef __linux__
					et->allocations = malloc(sizeof(struct epoll_event) * et->allocCap);
#elif __APPLE__
					et->allocations = malloc(sizeof(struct kevent) * et->allocCap);
#endif
					free(freePTR);
				}
				break;
		}
	}
}

eventtrigger_ptr_t et_alloc() {
	return malloc(sizeof(eventtrigger_t));
}

int et_init(eventtrigger_ptr_t et, readpipeline rp, writepipeline wp) {
	et->allocCap = 32;
#ifdef __APPLE__
	et->allocations = malloc(sizeof(struct kevent) * et->allocCap);
	et->pollqueue = kqueue();
#elif __linux__
	et->allocations = malloc(sizeof(struct epoll_event) * et->allocCap);
	et->pollqueue = epoll_create1(0);
#endif
	if (et->pollqueue == -1) {
		free(et->allocations);
		return errno;
	}
	et->readBuffer = malloc(PIPE_BUF);
	et->bufferCap = PIPE_BUF;
	if (hashmap_create(16, &et->enabledHandles) != 0) {
		return 1;
	}

	pthread_t newthread;
	int newThreadResult = pthread_create(&newthread, NULL, mainLoop, et);
	if (newThreadResult != 0) {
		close(et->pollqueue);
		free(et->allocations);
		free(et->readBuffer);
		return newThreadResult;
	}
	struct sched_param loopPri = {
		.sched_priority = 99
	};
	pthread_setschedparam(newthread, SCHED_FIFO, &loopPri);
	et->mainLoop = newthread;
	et->rpipe = rp;
	et->wpipe = wp;
	atomic_store_explicit(&et->tlock, NULL, memory_order_release);
	return 0;
}

int et_close(eventtrigger_ptr_t et) {
	pthread_ptr_t expectedPtr = NULL;
	const pthread_t tid = pthread_self();
	while (atomic_compare_exchange_strong_explicit(&et->tlock, &expectedPtr, &tid, memory_order_acq_rel, memory_order_relaxed) == false) {
		usleep(500);
		expectedPtr = NULL;
	}
	
	int signalResult = pthread_kill(et->mainLoop, SIGIO);
	if (signalResult != 0) {
		return signalResult;
	}
	int cancelResult = pthread_cancel(et->mainLoop);
	if (cancelResult != 0) {
		return cancelResult;
	}
	int joinResult = pthread_join(et->mainLoop, NULL);
	if (joinResult != 0) {
		return joinResult;
	}
	int closeResult = close(et->pollqueue);
	if (closeResult != 0) {
		return closeResult;
	}
	hashmap_destroy(&et->enabledHandles);

	free(et->readBuffer);
	free(et->allocations);
	free(et);
	return 0;
}


// register a writer
// - the registered file handle is automatically deregistered and closed if the corresponding reading fh is closed
int et_w_register(const eventtrigger_ptr_t et, const int fh, const usr_ptr_t usrPtr, const writerinfo_ptr_t writerinfo) {
	pthread_ptr_t expectedPtr = NULL;
	
	// acquire a tlock
	const pthread_t tid = pthread_self();
	while (atomic_compare_exchange_weak_explicit(&et->tlock, &expectedPtr, &tid, memory_order_acq_rel, memory_order_relaxed) == false) {
		usleep(500);
		expectedPtr = NULL;
	}
	
	// mark the writerinfo as opened
	wi_open(writerinfo, fh, et, usrPtr);
	
	// install the readerinfo in the hashmap
	if (hashmap_put(&et->enabledHandles, writerinfo->fhStr, writerinfo->fhStrLen, writerinfo) != 0) {
		wi_close(writerinfo);
		atomic_store_explicit(&et->tlock, NULL, memory_order_release);
		return 1;
	}
	
	// increment the termination group
	if (tg_increment(writerinfo->tg) != 0) {
		wi_close(writerinfo);
		hashmap_remove(&et->enabledHandles, writerinfo->fhStr, writerinfo->fhStrLen);
		atomic_store_explicit(&et->tlock, NULL, memory_order_release);
		return 1;
	}
	
#ifdef __linux__
	struct epoll_event regEvent;
	regEvent.data.fh = fh;
	regEvent.events = EPOLLOUT | EPOLLERR | EPOLLHUP | EPOLLET;
	int registerResult = epoll_ctl(et->pollqueue, EPOLL_CTL_ADD, fh, &regEvent);
#elif __APPLE__
	struct kevent newEvent;
	newEvent.ident = fh;
	newEvent.flags = EV_ADD | EV_CLEAR | EV_EOF;
	newEvent.filter = EVFILT_WRITE;
	newEvent.fflags = 0;
	newEvent.data = 0;
	newEvent.udata = NULL;
	int registerResult = kevent(et->pollqueue, &newEvent, 1, NULL, 0, NULL);
#endif
	
	if (registerResult != 0) {
		tg_decrement(writerinfo->tg);
		wi_close(writerinfo);
		hashmap_remove(&et->enabledHandles, writerinfo->fhStr, writerinfo->fhStrLen);
		// release lock
		atomic_store_explicit(&et->tlock, NULL, memory_order_release);
		return errno;
	}
	// release lock
	atomic_store_explicit(&et->tlock, NULL, memory_order_release);
	return 0;
}

// register a reader
// - the registered file handle is automatically deregistered and closed if the corresponding writing handle is closed
// - the readerinfo_ptr_t argument must have a valid termination group assigned to it before calling this function
int et_r_register(const eventtrigger_ptr_t et, const int fh, const uint8_t*_Nullable matchpat, const uint8_t matchpatlen, usr_ptr_t usrPtr, const readerinfo_ptr_t readerinfo) {
	pthread_ptr_t expectedPtr = NULL;
	
	// acquire a tlock
	const pthread_t tid = pthread_self();
	while (atomic_compare_exchange_weak_explicit(&et->tlock, &expectedPtr, &tid, memory_order_acq_rel, memory_order_relaxed) == false) {
		usleep(500);
		expectedPtr = NULL;
	}

	// mark the readerinfo as open
	ri_open(readerinfo, fh, et, matchpat, matchpatlen, usrPtr);
	
	// install the readerinfo in the hashmap
	if (hashmap_put(&et->enabledHandles, readerinfo->fhStr, readerinfo->fhStrLen, readerinfo) != 0) {
		lp_close_dataloss(&readerinfo->lp);
		ri_close(readerinfo);
		atomic_store_explicit(&et->tlock, NULL, memory_order_release);
		return 1;
	}
	
	// increment the termination group
	if (tg_increment(readerinfo->tg) != 0) {
		lp_close_dataloss(&readerinfo->lp);
		ri_close(readerinfo);
		hashmap_remove(&et->enabledHandles, ri_fhPtr(readerinfo), sizeof(int));
		atomic_store_explicit(&et->tlock, NULL, memory_order_release);
		return 1;
	}
	
	// platform specific implementations - register the file handle with the operating system
#ifdef __linux__
	struct epoll_event regEvent;
	regEvent.data.fh = fh;
	regEvent.events = EPOLLIN | EPOLLERR | EPOLLHUP | EPOLLET;
	int registerResult = epoll_ctl(et->pollqueue, EPOLL_CTL_ADD, fh, &regEvent);
#elif __APPLE__
	struct kevent newEvent;
	newEvent.ident = fh;
	newEvent.flags = EV_ADD | EV_CLEAR | EV_EOF;
	newEvent.filter = EVFILT_READ;
	newEvent.fflags = 0;
	newEvent.data = 0;
	newEvent.udata = NULL;
	int registerResult = kevent(et->pollqueue, &newEvent, 1, NULL, 0, NULL);
#endif
	
	// check the result of the registration
	if (registerResult != 0) {
		tg_decrement(readerinfo->tg);
		hashmap_remove(&et->enabledHandles, readerinfo->fhStr, readerinfo->fhStrLen);
		
		// purge the lineparser that was just created
		lp_close_dataloss(&readerinfo->lp);
		ri_close(readerinfo);
		
		// release the tlock
		atomic_store_explicit(&et->tlock, NULL, memory_order_release);
		return errno;
	}
	
	// release the tlock
	atomic_store_explicit(&et->tlock, NULL, memory_order_release);
	return 0;
}
