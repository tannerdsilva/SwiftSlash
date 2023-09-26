#ifndef CLIBSWIFTSLASH_WRITERINFO_H
#define CLIBSWIFTSLASH_WRITERINFO_H

#include "types.h"
#include "terminationgroup.h"
#include "writerchain.h"

/// defines a structure that contains information about a writer handle.
/// this structure is self deallocating based on the conditions listed below:
/// - this is to remain in memory while the file handle is open.
/// - this is to remain in memory while the structure is "held" by the external developer.
typedef struct writerinfo {
	/// the termination group to which this writer belongs.
	_Atomic terminationgroup_optr_t tg;
	/// the file handle to which this writer writes.
	const int fh;
	/// the writer chain for this writer.
	writerchainpair_t writer;
	/// documents whether this writer is open.
	_Atomic bool isOpen;
	/// documents whether this writer is writable.
	_Atomic bool isWritable;
	/// documents whether this writer is held by the external developer.
	_Atomic bool isHeld;
} writerinfo_t;

/// represents a non-null pointer to a writerinfo structure.
typedef writerinfo_t*_Nonnull writerinfo_ptr_t;

/// @brief initializes a writerinfo structure.
writerinfo_t wi_init();

// this structure is self deallocating (at either ``wi_unhold()`` or ``wi_close()``).

/// @brief attempts to unhold a writerinfo structure.
/// @param wi a pointer to the writerinfo structure to unhold.
/// @return true if the writerinfo structure was successfully marked as unheld, false otherwise (indicating a severe internal error)
bool wi_unhold(const writerinfo_ptr_t wi);

/// @brief attempts to mark a writerinfo structure as closed.
/// @param wi a pointer to the writerinfo structure to close.
/// @return true if the writerinfo structure was successfully marked as closed, false otherwise (indicating a severe internal error)
bool wi_close(const writerinfo_ptr_t wi);

/// @brief writes data to a writerinfo structure. if the writerinfo structure happens to be writable, a write will be attempted.
/// @param wi a pointer to the writerinfo structure to write to.
/// @param data a pointer to the data to write.
/// @param datalen the length of the data to write.
/// @return true if the writerinfo structure is still open and functional (not necessarily writable at this moment). false if the writerinfo structure is closed and indefinitely nonfunctional.
bool wi_write(const writerinfo_ptr_t wi, const data_ptr_t data, const size_t datalen);

/// @brief flushes a writerinfo structure to its file handle.
/// @param wi a pointer to the writerinfo structure to flush.
/// @return true if the flush was successful. false if the flush failed.
bool wi_flush(const writerinfo_ptr_t wi);

/// @brief sets a writerinfo structure to be writable.
/// @param wi a pointer to the writerinfo structure to set.
/// @return true if the writerinfo structure is still open and functional (not necessarily writable at this moment).
bool wi_set_writable(const writerinfo_ptr_t wi);

/// @brief assigns a termination group to a writerinfo structure.
/// @param wi a pointer to the writerinfo structure to assign to.
/// @param tg a pointer to the termination group to assign.
void wi_assign_tg(const writerinfo_ptr_t wi, const terminationgroup_ptr_t tg);

#endif //CLIBSWIFTSLASH_WRITERINFO_H