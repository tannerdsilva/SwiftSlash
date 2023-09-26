#include "include/writerinfo.h"

#include <string.h>
#include <errno.h>
#include <stdlib.h>
#include <stdatomic.h>

writerinfo_t wi_init() {
	const writerinfo_t newwi = {
		.tg = NULL,
		.fh = 0,
		.writer = wcp_init(),
		.isOpen = true,
		.isWritable = true,
		.isHeld = true
	};
	return newwi;
}

/// @brief deallocates a writerinfo structure.
/// @param wi a pointer to the writerinfo structure to deallocate.
void wi_dealloc(const writerinfo_ptr_t wi) {
	// close the writer chain. this will free any pending data that was not written.
	wcp_close(&wi->writer);

	// free the writerinfo structure itself.
	free(wi);
}

bool wi_unhold(const writerinfo_ptr_t wi) {
	// read and write the atomic values of wi in order...
	// start with isOpen...
	if (atomic_load_explicit(&wi->isOpen, memory_order_acquire) == true) {
		// the file handle is open, so we can't close the writerinfo structure.
		bool expectedHeldValue = true;
		return atomic_compare_exchange_strong_explicit(&wi->isHeld, &expectedHeldValue, false, memory_order_acq_rel, memory_order_acquire);
	} else {
		// the file handle is not open, so we can close the writerinfo structure and the structures it contains.
		// change the held value from true to false
		bool expectedHeldValue = true;
		if (atomic_compare_exchange_strong_explicit(&wi->isHeld, &expectedHeldValue, false, memory_order_acq_rel, memory_order_acquire) == false) {
			// the item was not the expected value and therefore NOT assigned.
			// this means that someone else is working to free the structure, so we should return failure and do nothing (dont want to double free).
			return false; // failure
		} else {
			// the item was the expected value and therefore assigned.
			// this means it is our responsibility to free the structure.
			wi_dealloc(wi);
			return true; // success
		}
	}
}

bool wi_close(const writerinfo_ptr_t wi) {
	// read and write the atomic values of wi in order...
	// start with isOpen...
	if (atomic_load_explicit(&wi->isOpen, memory_order_acquire) == true) {
		// the file handle is open, so we can close the writerinfo structure.
		// change the open value from true to false
		bool expectedOpenValue = true;
		if (atomic_compare_exchange_strong_explicit(&wi->isOpen, &expectedOpenValue, false, memory_order_acq_rel, memory_order_acquire) == false) {
			// the item was not the expected value and therefore NOT assigned.
			// this means that someone else is working to close the structure, so we should return failure and do nothing (dont want to double close).
			return false; // failure
		} else {
			// the item was the expected value and therefore assigned.
			// this means it is our responsibility to close the structure.
			wi_dealloc(wi);
			return true; // success
		}
	} else {
		// the file handle is not open, so we can't close the writerinfo structure.
		bool expectedOpenValue = false;
		return atomic_compare_exchange_strong_explicit(&wi->isOpen, &expectedOpenValue, false, memory_order_acq_rel, memory_order_acquire);
	}
}

bool wi_write(const writerinfo_ptr_t wi, const data_ptr_t data, const size_t datalen) {
	wc_append(&wi->writer, data, datalen);
	if (atomic_load_explicit(&wi->isOpen, memory_order_acquire) == false) {
		// the file handle is not open, so we can't write to the writerinfo structure.
		return false; // not open
	} else {
		bool isWritable = atomic_load_explicit(&wi->isWritable, memory_order_acquire);
		if (isWritable == true) {
			// if the handle is writable, flush the buffer
			int err;
			bool hadError = wc_flush(&wi->writer, wi->fh, &err);
			if (err != 0) {
				atomic_store_explicit(&wi->isWritable, false, memory_order_release);
			}
		}
		return true; // still open
	}
}

bool wi_flush(const writerinfo_ptr_t wi) {
	if (atomic_load_explicit(&wi->isOpen, memory_order_acquire) == false) {
		// the file handle is not open, so we can't flush the writerinfo structure.
		return false;
	} else {
		if (atomic_load_explicit(&wi->isWritable, memory_order_acquire) == false) {
			// the file handle is not writable, so we can't flush the writerinfo structure.
			return false; // failure.
		} else {
			// the file handle is writable, so we can try and flush the pending data.
			int err;
			bool hadError = wc_flush(&wi->writer, wi->fh, &err);
			if (err != 0) {
				atomic_store_explicit(&wi->isWritable, false, memory_order_release);
			}
			return !hadError; // success if there was no error
		}
	}
}

bool wi_set_writable(const writerinfo_ptr_t wi) {
	if (atomic_load_explicit(&wi->isOpen, memory_order_acquire) == false) {
		// the file handle is not open, so we can't set the writerinfo structure to be writable.
		return false; // failure
	} else {
		atomic_store_explicit(&wi->isWritable, true, memory_order_release);
		int err;
		bool hadError = wc_flush(&wi->writer, wi->fh, &err);
		if (err != 0) {
			atomic_store_explicit(&wi->isWritable, false, memory_order_release);
		}
		return true; // success
	}
}

void wi_assign_tg(const writerinfo_ptr_t wi, const terminationgroup_ptr_t tg) {
	atomic_store_explicit(&wi->tg, tg, memory_order_release);
}
