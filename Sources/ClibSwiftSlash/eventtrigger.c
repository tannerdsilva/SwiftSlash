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

#ifdef __linux__
#include <sys/epoll.h>
#elif __APPLE__
#include <sys/event.h>
#endif


int et_w_deregister(eventtrigger *et, writerinfo_t *wi) {
#ifdef __linux__
	struct epoll_event regEvent;
	regEvent.data.ptr = wi;
	regEvent.events = EPOLLOUT | EPOLLERR | EPOLLHUP | EPOLLET;
	int registerResult = epoll_ctl(et->pollqueue, EPOLL_CTL_DEL, wi->fh, &regEvent);
	if (registerResult != 0) {
		return errno;
	}
	return 0;
#elif __APPLE__
	struct kevent newEvent;
	newEvent.ident = ri->fh;
	newEvent.flags = EV_DELETE | EV_CLEAR | EV_EOF;
	newEvent.filter = EVFILT_WRITE;
	newEvent.fflags = 0;
	newEvent.data = 0;
	newEvent.udata = NULL;
	int registerResult = kevent(et->pollqueue, &newEvent, 1, NULL, 0, NULL);
	if (registerResult != 0) {
		return errno;
	}
	return 0;
#endif
}

int et_r_deregister(eventtrigger *et, readerinfo_t *ri) {
#ifdef __linux__
	struct epoll_event regEvent;
	regEvent.data.ptr = ri;
	regEvent.events = EPOLLIN | EPOLLERR | EPOLLHUP | EPOLLET;
	int registerResult = epoll_ctl(et->pollqueue, EPOLL_CTL_DEL, ri->fh, &regEvent);
	if (registerResult != 0) {
		return errno;
	}
	return 0;
#elif __APPLE__
	struct kevent newEvent;
	newEvent.ident = ri->fh;
	newEvent.flags = EV_DELETE | EV_CLEAR | EV_EOF;
	newEvent.filter = EVFILT_READ;
	newEvent.fflags = 0;
	newEvent.data = 0;
	newEvent.udata = NULL;
	int registerResult = kevent(et->pollqueue, &newEvent, 1, NULL, 0, NULL);
	if (registerResult != 0) {
		return errno;
	}
	return 0;
#endif
}

void et_validate_readsize(eventtrigger *et, size_t readsize) {
	if (readsize > et->bufferCap) {
		et->bufferCap = et->bufferCap * 2;
		free(et->readBuffer);
		et->readBuffer = malloc(et->bufferCap);
	}
}

void* mainLoop(void *argc) {
	eventtrigger* et = ((eventtrigger*)argc);
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
						if (ioctl(((readerinfo_t*)(et->allocations[i].data.ptr))->fh, FIONREAD, &readableSize) != 0) {
							printf("ioctl error %i", ((readerinfo_t*)(et->allocations[i].data.ptr))->fh);
						}
						
						//resize the read buffer if necessary, based on the number of readable bytes for this fh
						et_validate_readsize(et, readableSize);
						
						//read the data
						size_t readresult;
						do {
							readresult = read(((readerinfo_t*)(et->allocations[i].data.ptr))->fh, et->readBuffer, readableSize);
						} while (readresult == EAGAIN || readresult == EINTR);
						
						//deregister the fh from the pollqueue
						const int deregisterResult = et_r_deregister(et, (readerinfo_t*)et->allocations[i].data.ptr);
						if (deregisterResult != 0) {
							printf("DEREG ERROR\n");
						}
						
						//close the file handle
						int closeResult;
						do {
							closeResult = close(((readerinfo_t*)et->allocations[i].data.ptr)->fh);
						} while (closeResult == EINTR);
						if (closeResult < 0) {
							printf("CLOSE FAILED\n");
						}
						
						//call the handler
						if (readresult >= 0) {
							(((readerinfo_t*)(et->allocations[i].data.ptr))->handler)(((readerinfo_t*)(et->allocations[i].data.ptr))->fh, et->readBuffer, readresult, true);
						} else {
							printf("READ RESULT ERROR\n");
						}
					} else if (et->allocations[i].events & EPOLLERR) {
						//writing closed
						
						//deregister the fh from the pollqueue
						const int deregisterResult = et_w_deregister(et, ((writerinfo_t*)(et->allocations[i].data.ptr)));
						if (deregisterResult != 0) {
							printf("DEREG ERROR\n");
						}
						
						//close the file handle
						int closeResult;
						do {
							closeResult = close(((writerinfo_t*)et->allocations[i].data.ptr)->fh);
						} while (closeResult == EINTR);
						if (closeResult < 0) {
							printf("CLOSE FAILED\n");
						}
						
						//call the handler
						(((writerinfo_t*)(et->allocations[i].data.ptr))->handler)(((writerinfo_t*)(et->allocations[i].data.ptr))->fh, true);
					} else if (et->allocations[i].events & EPOLLIN) {
						//reading available
						
						//determine how many bytes can be read
						size_t readableSize = 0;
						if (ioctl(((readerinfo_t*)(et->allocations[i].data.ptr))->fh, FIONREAD, &readableSize) != 0) {
							printf("ioctl error %i", ((readerinfo_t*)(et->allocations[i].data.ptr))->fh);
						}
						
						//resize the read buffer if necessary, based on the number of readable bytes for this fh
						et_validate_readsize(et, readableSize);
						
						//read the data
						size_t readresult;
						do {
							readresult = read(((readerinfo_t*)(et->allocations[i].data.ptr))->fh, et->readBuffer, readableSize);
						} while (readresult == EAGAIN || readresult == EINTR);
						
						
						if (readresult >= 0) {
							(((readerinfo_t*)(et->allocations[i].data.ptr))->handler)(((readerinfo_t*)(et->allocations[i].data.ptr))->fh, et->readBuffer, readableSize, false);
						} else {
							printf("READ RESULT ERROR\n");
						}
					} else if (et->allocations[i].events & EPOLLOUT) {
						//writing available
						(((writerinfo_t*)(et->allocations[i].data.ptr))->handler)(((writerinfo_t*)(et->allocations[i].data.ptr))->fh, false);
					}
					i = i + 1;
				}

#elif __APPLE__
				while (i < result) {
					if ((et->allocations[i].flags & EV_EOF) == 0) {
						if (et->allocations[i].filter == EVFILT_READ) {
							const size_t readableSize = et->allocations[i].data;
							((readhandler)(et->allocations[i].udata))(et->allocations[i].ident, readableSize, false);
						} else if (et->allocations[i].filter == EVFILT_WRITE) {
							((writehandler)(et->allocations[i].udata))(et->allocations[i].ident, false);
						}
					} else {
						if (et->allocations[i].filter == EVFILT_READ) {
							const size_t readableSize = et->allocations[i].data;
							const int deregisterResult = et_r_deregister(et, et->allocations[i].ident);
							if (deregisterResult == EINTR) {
								pthread_exit(NULL);
							}
							((readhandler)(et->allocations[i].udata))(et->allocations[i].ident, readableSize, true);
						} else if (et->allocations[i].filter == EVFILT_WRITE) {
							const int deregisterResult = et_w_deregister(et, et->allocations[i].ident);
							if (deregisterResult == EINTR) {
								pthread_exit(NULL);
							}
							((writehandler)(et->allocations[i].udata))(et->allocations[i].ident, true);
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

eventtrigger* et_alloc() {
	return malloc(sizeof(eventtrigger));
}

int et_init(eventtrigger *et) {
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
	return 0;
}

int et_close(eventtrigger *et) {
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

int et_w_register(const eventtrigger *et, const writerinfo_t *wi) {
#ifdef __linux__
	struct epoll_event regEvent;
	regEvent.data.ptr = (void*)wi;
	regEvent.events = EPOLLOUT | EPOLLERR | EPOLLHUP | EPOLLET;
	int registerResult = epoll_ctl(et->pollqueue, EPOLL_CTL_ADD, wi->fh, &regEvent);
	if (registerResult != 0) {
		return errno;
	}
	return 0;
#elif __APPLE__
	struct kevent newEvent;
	newEvent.ident = fh;
	newEvent.flags = EV_ADD | EV_CLEAR | EV_EOF;
	newEvent.filter = EVFILT_WRITE;
	newEvent.fflags = 0;
	newEvent.data = 0;
	newEvent.udata = wh;
	int registerResult = kevent(et->pollqueue, &newEvent, 1, NULL, 0, NULL);
	if (registerResult != 0) {
		return errno;
	}
	return 0;
#endif
}

int et_r_register(const eventtrigger *et, const readerinfo_t *ri) {
#ifdef __linux__
	struct epoll_event regEvent;
	regEvent.data.ptr = (void*)ri;
	regEvent.events = EPOLLIN | EPOLLERR | EPOLLHUP | EPOLLET;
	int registerResult = epoll_ctl(et->pollqueue, EPOLL_CTL_ADD, ri->fh, &regEvent);
	if (registerResult != 0) {
		return errno;
	}
	return 0;
#elif __APPLE__
	struct kevent newEvent;
	newEvent.ident = fh;
	newEvent.flags = EV_ADD | EV_CLEAR | EV_EOF;
	newEvent.filter = EVFILT_READ;
	newEvent.fflags = 0;
	newEvent.data = 0;
	newEvent.udata = rh;
	int registerResult = kevent(et->pollqueue, &newEvent, 1, NULL, 0, NULL);
	if (registerResult != 0) {
		return errno;
	}
	return 0;
#endif
}