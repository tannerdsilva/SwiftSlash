#include "writerchain.h"

#include <stdlib.h>
#include <string.h>
#include <stdatomic.h>
#include <unistd.h>
#include <errno.h>
#include <stdio.h>

/// @brief internal function. appends a pre-allocated writerchain_ptr_t to a given writerchain.
/// @param base the base of the chain to append to.
/// @param tail the tail of the chain to append to.
/// @param newentry the entry to append.
/// @return boolean indicating whether the append was successful.
bool wc_append_wc_ptr(const writerchain_aptr_ptr_t base, const writerchain_aptr_ptr_t tail, writerchain_ptr_t newentry) {
	
	// the required value that must exist in place of our new entry
	writerchain_ptr_t expected = NULL;
	
	// load the current tail entry. it may exist, or it may not.
	writerchain_ptr_t currentTailEntry = atomic_load_explicit(tail, memory_order_acquire);
	
	// determine where to try and write the new entry based on whether or not there is a tail entry
	writerchain_aptr_t*_Nonnull writeTo;
	if (currentTailEntry == NULL) {
		writeTo = tail;
	} else { 
		writeTo = &currentTailEntry->next;
	}

	// attempt to store the new value to the end of the chain.
	bool storeResult = atomic_compare_exchange_strong_explicit(writeTo, &expected, newentry, memory_order_acq_rel, memory_order_relaxed);
	if (storeResult == true) {
		
		// update the base and tail pointers based on how the store was applied to the chain.
		if (currentTailEntry == NULL) {
			atomic_store_explicit(base, newentry, memory_order_release);
		} else {
			atomic_store_explicit(tail, newentry, memory_order_release);
		}
	}

	// return the result.
	return storeResult;
}

void wc_append(const writerchain_aptr_ptr_t base, const writerchain_aptr_ptr_t tail, const data_ptr_t data, const size_t datalen) {
	const struct writerchain newchain = {
		.data = memcpy(malloc(datalen), data, datalen),
		.datasize = datalen,
		.written = 0,
		.next = NULL
	};
	const writerchain_ptr_t newentry = memcpy(malloc(sizeof newchain), &newchain, sizeof(newchain));
	bool current = false;
	do {
		current = wc_append_wc_ptr(base, tail, newentry);
	} while (current == false);
}

/// should only be handled in 8 bit values.
typedef enum wc_flush_signal {
	wc_flush_success_exit = 0,	// indicates success with no need to retry the current entry or iterate to the next. causes an exit.
	wc_flush_success_continue = 1,	// indicates success with the current entry and that we should proceed to the next entry. causes a new iteration on the next chain item, if it exists.
	wc_flush_failure = 3,		// indicates failure with the current entry.
} wc_flush_signal_t;

/// @brief internal function that moves the base and tail pointers to the next entry.
/// @param current the pre-loaded atomic pointer to the current entry.
/// @param base the base of the chain to flush.
/// @param tail the tail of the chain to flush.
void wc_move_next(const writerchain_ptr_t current, const writerchain_aptr_ptr_t base, const writerchain_aptr_ptr_t tail) {
	// load the next entry.
	writerchain_ptr_t next = atomic_load_explicit(&current->next, memory_order_acquire);
	
	// update the base and tail pointers based on how the store was applied to the chain.
	if (next == NULL) {
		atomic_store_explicit(tail, NULL, memory_order_release);
	} else {
		atomic_store_explicit(base, next, memory_order_release);
	}

	// free the current entry.
	free((void*)current->data);
	free((void*)current);
}

/// @brief internal function that flushes a single writerchain entry.
/// @param base the base of the chain to flush.
/// @param tail the tail of the chain to flush.
/// @param fd the file descriptor to write to.
/// @param err a pointer to an integer that will be set to the error code if the function returns false.
/// @return a signal indicating whether the flush was successful, and if so, whether to proceed to the next entry or exit.
wc_flush_signal_t wc_flush_single(const writerchain_aptr_ptr_t base, const writerchain_aptr_ptr_t tail, const int fd, const err_ptr_t err) {
	// load the base entry.
	writerchain_ptr_t getbase = atomic_load_explicit(base, memory_order_acquire);
	if (getbase == NULL) {
		// there are no entries, return the success complete signal.
		(*err) = 0;
		return wc_flush_success_exit;
	}
	
	// check the written bytes for this entry.
	size_t writtenbytes = atomic_load_explicit(&getbase->written, memory_order_acquire);
	
	// act based on the knowledge of the current bytes written on this entry.
	if (writtenbytes < getbase->datasize) {
		// there are more bytes to write. so lets write them...
		int currentresult = write(fd, getbase->data + writtenbytes, getbase->datasize - writtenbytes);
		if (currentresult >= 0) {
			// write success. determine if we just completed the entry.
			atomic_fetch_add_explicit(&getbase->written, currentresult, memory_order_acq_rel);
			if ((writtenbytes + currentresult) == (getbase->datasize)) {
				// all of the data flushed. proceed to next.
				wc_move_next(getbase, base, tail);
				return wc_flush_success_continue;
			} else {
				// there is more data to flush on this item and we should stay here.
				return wc_flush_success_continue;
			}
		} else {
			// write failure. return the error.
			(*err) = errno;
			return wc_flush_failure;
		}
	} else { 
		// all of the bytes have already been flushed so we need to proceed to the next entry.
		wc_move_next(getbase, base, tail);
		return wc_flush_success_continue;
	}
}

bool wc_flush(const writerchain_aptr_ptr_t base, const writerchain_aptr_ptr_t tail, const int fd, const err_ptr_t err) {
	(*err) = 0;

	// iterate until either failure or exit is called.
	unsigned int succ = 0;
	while (true) {
		switch (wc_flush_single(base, tail, fd, err)) {
			case wc_flush_success_exit:
				return true;
			case wc_flush_success_continue:
				succ += 1;
				continue;
			case wc_flush_failure:
				// any number of successful flushes is a success.
				if (succ > 0) {
					return true;
				}
				// do not cascade a failure when the buffer is full.
				if (*err == EAGAIN || *err == EWOULDBLOCK) {
					return true;
				}
				return false;
		}
	}
}

// deinitialize a given writerchain
void wc_close(const writerchain_aptr_ptr_t base, const writerchain_aptr_ptr_t tail) {
	// load the base entry.
	writerchain_ptr_t getbase = atomic_load_explicit(base, memory_order_acquire);
	if (getbase == NULL) {
		// there are no entries, return the success complete signal.
		return;
	}
	
	// iterate through the chain and free all entries.
	writerchain_ptr_t current = getbase;
	while (current != NULL) {
		writerchain_ptr_t next = atomic_load_explicit(&current->next, memory_order_acquire);
		free((void*)current->data);
		free((void*)current);
		current = next;
	}
	
	// set the base and tail to NULL.
	atomic_store_explicit(base, NULL, memory_order_release);
	atomic_store_explicit(tail, NULL, memory_order_release);
}