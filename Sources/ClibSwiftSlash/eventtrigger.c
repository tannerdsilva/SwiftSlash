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

#ifdef __linux__
#include <sys/epoll.h>
#elif __APPLE__
#include <sys/event.h>
#endif

// initialize writer info
writerinfo_ptr_t wi_init(terminationgroup_ptr_t tg) {
	writerinfo_ptr_t pointer = malloc(sizeof(writerinfo_t));
	pointer->tg = tg;
	tg_increment(tg);
	pointer->chain = NULL;
	pointer->fh = -1;
	pointer->isWritable = false;
	pointer->isOpen = false;
	pointer->isHeld = true;
	return pointer;
}

void wi_unhold(writerinfo_ptr_t info) {
	chaintail loadedChain = atomic_load_explicit(&info->chain, memory_order_acquire);
	if (info->isHeld == true) {
		info->isHeld = false;
	}
	if (info->isOpen == false) {
		wc_close(&loadedChain);
		atomic_store_explicit(&info->chain, loadedChain, memory_order_release);
		free(info);
	} else {
		atomic_store_explicit(&info->chain, loadedChain, memory_order_release);
	}
}
void wi_close(writerinfo_ptr_t info) {
	chaintail loadedChain = atomic_load_explicit(&info->chain, memory_order_acquire);
	tg_decrement(info->tg);
	if (info->isWritable == true) {
		info->isWritable = false;
	}
	if (info->isOpen == true) {
		info->isOpen = false;
	}
	if (info->isHeld == false) {
		wc_close(&loadedChain);
		atomic_store_explicit(&info->chain, loadedChain, memory_order_release);
		free(info);
	} else {
		atomic_store_explicit(&info->chain, loadedChain, memory_order_release);
	}
}
void wi_setWritable(writerinfo_ptr_t info) {
	int err;
	chaintail loadedChain = atomic_load_explicit(&info->chain, memory_order_acquire);
	if (info->isOpen == true) {
		wc_flush(&loadedChain, info->fh, &err);
		if (err != 0) {
			info->isWritable = false;
		} else {
			info->isWritable = true;
		}
	}
	atomic_store_explicit(&info->chain, loadedChain, memory_order_release);
}
void wi_write(writerinfo_ptr_t info, const uint8_t *buff, const size_t bufflen) {
	chaintail loadedChain = atomic_load_explicit(&info->chain, memory_order_acquire);
	wc_append(&loadedChain, buff, bufflen);
	if (info->isWritable == true) {
		int err;
		wc_flush(&loadedChain, info->fh, &err);
		if (err != 0) {
			info->isWritable = false;
		}
	}
	atomic_store_explicit(&info->chain, loadedChain, memory_order_release);
}

readerinfo_ptr_t ri_init(terminationgroup_ptr_t tg) {
	readerinfo_ptr_t pointer = malloc(sizeof(readerinfo_t));
	pointer->fh = -1;
	pointer->isOpen = false;
	pointer->isHeld = true;
	tg_increment(tg);
	pointer->tg = tg;
	atomic_store(&pointer->usrPtr, NULL);
	return pointer;
}

void ri_close(const readerinfo_ptr_t ri) {
	usr_ptr_t loadedPtr = atomic_load_explicit(&ri->usrPtr, memory_order_acquire);
	if (ri->isOpen == true) {
		ri->isOpen = false;
	}
	tg_decrement(ri->tg);
	if (ri->isHeld == false) {
		atomic_store_explicit(&ri->usrPtr, loadedPtr, memory_order_release);
		free(ri);
	} else {
		atomic_store_explicit(&ri->usrPtr, loadedPtr, memory_order_release);
	}
}
void ri_unhold(const readerinfo_ptr_t ri) {
	usr_ptr_t loadedPtr = atomic_load_explicit(&ri->usrPtr, memory_order_acquire);
	if (ri->isHeld == true) {
		ri->isHeld = false;
	}
	if (ri->isOpen == false) {
		atomic_store_explicit(&ri->usrPtr, loadedPtr, memory_order_release);
		free(ri);
	} else {
		atomic_store_explicit(&ri->usrPtr, loadedPtr, memory_order_release);
	}
}

void lphandler(const uint8_t*_Nonnull inbuff, const size_t bufflen, usr_ptr_t usrPtr) {
	usr_ptr_t getUsrPtr = atomic_load_explicit(&(((readerinfo_ptr_t)usrPtr)->usrPtr), memory_order_acquire);
	((readerinfo_ptr_t)usrPtr)->et->rpipe(inbuff, bufflen, false, getUsrPtr);
}

int et_w_deregister(const eventtrigger_ptr_t et, const writerinfo_ptr_t wi) {
#ifdef __linux__
	struct epoll_event regEvent;
	regEvent.data.ptr = wi;
	regEvent.events = EPOLLOUT | EPOLLERR | EPOLLHUP | EPOLLET;
	int registerResult = epoll_ctl(et->pollqueue, EPOLL_CTL_DEL, wi->fh, &regEvent);
#elif __APPLE__
	struct kevent newEvent;
	newEvent.ident = wi->fh;
	newEvent.flags = EV_DELETE | EV_CLEAR | EV_EOF;
	newEvent.filter = EVFILT_WRITE;
	newEvent.fflags = 0;
	newEvent.data = 0;
	newEvent.udata = wi;
	int registerResult = kevent(et->pollqueue, &newEvent, 1, NULL, 0, NULL);
#endif
	if (registerResult != 0) {
		return errno;
	}
	wi_close(wi);
	return 0;
}

int et_r_deregister(const eventtrigger_ptr_t et, const readerinfo_ptr_t ri) {
#ifdef __linux__
	struct epoll_event regEvent;
	regEvent.data.ptr = ri;
	regEvent.events = EPOLLIN | EPOLLERR | EPOLLHUP | EPOLLET;
	int registerResult = epoll_ctl(et->pollqueue, EPOLL_CTL_DEL, ri->fh, &regEvent);
#elif __APPLE__
	struct kevent newEvent;
	newEvent.ident = ri->fh;
	newEvent.flags = EV_DELETE | EV_CLEAR | EV_EOF;
	newEvent.filter = EVFILT_READ;
	newEvent.fflags = 0;
	newEvent.data = 0;
	newEvent.udata = ri;
	int registerResult = kevent(et->pollqueue, &newEvent, 1, NULL, 0, NULL);
#endif
	if (registerResult != 0) {
		return errno;
	}
	ri_close(ri);
	return 0;
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
void _rAvail(readerinfo_ptr_t ptr, const size_t rsize) {
	// resize the read buffer
	et_validate_readsize(ptr->et, rsize);
	
	// read the data
	int readresult;
	do {
		readresult = read(ptr->fh, ptr->et->readBuffer, rsize);
	} while ((readresult < 0) && (errno == EAGAIN || errno == EINTR));
	
	// feed the newly captured data into the line parser
	if (readresult >= 0) {
		lp_intake(&ptr->lp, ptr->et->readBuffer, readresult, ptr, lphandler);
	} else {
		printf("READ RESULT ERROR %i\n", errno);
	}
}

// writing closed
void _wClose(writerinfo_ptr_t ptr) {
	// deregister the fh from the pollqueue
	int fhCapture = ptr->fh;
	int deregisterResult;
	do {
		deregisterResult = et_w_deregister(ptr->et, ptr);
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
	if (readresult >= 0) {
		lp_intake(&ptr->lp, ptr->et->readBuffer, readresult, ptr, lphandler);
	} else {
		printf("READ RESULT ERROR\n");
	}
	
	// close the line parser
	lp_close(&ptr->lp, ptr, lphandler);
	
	// deregister the file handle
	int fhCap = ptr->fh;
	int deregisterResult;
	do {
		deregisterResult = et_r_deregister(ptr->et, ptr);
	} while (deregisterResult == EINTR);
	
	// capture the user pointer, call the reader pipeline with the closed flag
	usr_ptr_t userPtr = atomic_load_explicit(&ptr->usrPtr, memory_order_acquire);
	ptr->et->rpipe(ptr->et->readBuffer, readresult, true, userPtr);

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
	while (1) {
		int i = 0;
		pthread_testcancel();
#ifdef __linux__
		const int result = epoll_wait(et->pollqueue, et->allocations, et->allocCap, -1);
#elif __APPLE__
		const int result = kevent(et->pollqueue, NULL, 0, et->allocations, et->allocCap, NULL);
#endif
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
#ifdef __linux__
				while (i < result) {
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
					if ((et->allocations[i].flags & EV_EOF) == 0) {
						if (et->allocations[i].filter == EVFILT_READ) {
							// reading available
							_rAvail(et->allocations[i].udata, et->allocations[i].data);
						} else if (et->allocations[i].filter == EVFILT_WRITE) {
							// writing available
							_wAvail(et->allocations[i].udata);
						}
					} else {
						if (et->allocations[i].filter == EVFILT_READ) {
							// reading closed
							_rClose(et->allocations[i].udata, et->allocations[i].data);
						} else if (et->allocations[i].filter == EVFILT_WRITE) {
							// writing closed
							_wClose(et->allocations[i].udata);
						}
					}
					i = i + 1;
				}
#endif
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
	
	pthread_t newthread;
	int newThreadResult = pthread_create(&newthread, NULL, mainLoop, et);
	if (newThreadResult != 0) {
		close(et->pollqueue);
		free(et->allocations);
		free(et->readBuffer);
		return newThreadResult;
	}
	et->mainLoop = newthread;
	et->rpipe = rp;
	et->wpipe = wp;
	return 0;
}

int et_close(eventtrigger_ptr_t et) {
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
	free(et->readBuffer);
	free(et->allocations);
	free(et);
	return 0;
}


// register a writer
// - the registered file handle is automatically deregistered and closed if the corresponding reading fh is closed
int et_w_register(const eventtrigger_ptr_t et, const int fh, const usr_ptr_t usrPtr, const writerinfo_ptr_t writerinfo) {
	chaintail loadedChain = atomic_load_explicit(&writerinfo->chain, memory_order_acquire);
	writerinfo->fh = fh;
	writerinfo->usrPtr = usrPtr;
	writerinfo->isOpen = true;
	writerinfo->et = et;
#ifdef __linux__
	struct epoll_event regEvent;
	regEvent.data.ptr = writerinfo;
	regEvent.events = EPOLLOUT | EPOLLERR | EPOLLHUP | EPOLLET;
	int registerResult = epoll_ctl(et->pollqueue, EPOLL_CTL_ADD, fh, &regEvent);
#elif __APPLE__
	struct kevent newEvent;
	newEvent.ident = fh;
	newEvent.flags = EV_ADD | EV_CLEAR | EV_EOF;
	newEvent.filter = EVFILT_WRITE;
	newEvent.fflags = 0;
	newEvent.data = 0;
	newEvent.udata = writerinfo;
	int registerResult = kevent(et->pollqueue, &newEvent, 1, NULL, 0, NULL);
#endif
	if (registerResult != 0) {
		writerinfo->isOpen = false;
		atomic_store_explicit(&writerinfo->chain, loadedChain, memory_order_release);
		return errno;
	}
	atomic_store_explicit(&writerinfo->chain, loadedChain, memory_order_release);
	return 0;
}

// register a reader
// - the registered file handle is automatically deregistered and closed if the corresponding writing handle is closed
int et_r_register(const eventtrigger_ptr_t et, const int fh, const uint8_t*_Nullable matchpat, const uint8_t matchpatlen, usr_ptr_t usrPtr, const readerinfo_ptr_t readerinfo) {
	usr_ptr_t loadedPtr = atomic_load_explicit(&readerinfo->usrPtr, memory_order_acquire);
	readerinfo->isOpen = true;
	readerinfo->fh = fh;
	readerinfo->et = et;
	readerinfo->lp = lp_init(matchpat, matchpatlen);
#ifdef __linux__
	struct epoll_event regEvent;
	regEvent.data.ptr = readerinfo;
	regEvent.events = EPOLLIN | EPOLLERR | EPOLLHUP | EPOLLET;
	int registerResult = epoll_ctl(et->pollqueue, EPOLL_CTL_ADD, fh, &regEvent);
#elif __APPLE__
	struct kevent newEvent;
	newEvent.ident = fh;
	newEvent.flags = EV_ADD | EV_CLEAR | EV_EOF;
	newEvent.filter = EVFILT_READ;
	newEvent.fflags = 0;
	newEvent.data = 0;
	newEvent.udata = readerinfo;
	int registerResult = kevent(et->pollqueue, &newEvent, 1, NULL, 0, NULL);
#endif
	if (registerResult != 0) {
		lp_close_dataloss(&readerinfo->lp);
		readerinfo->isOpen = false;
		atomic_store_explicit(&readerinfo->usrPtr, usrPtr, memory_order_release);
		return errno;
	}
	atomic_store_explicit(&readerinfo->usrPtr, usrPtr, memory_order_release);
	return 0;
}
