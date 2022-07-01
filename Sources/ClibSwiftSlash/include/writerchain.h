//
//  writerchain.c.h
//  
//
//  Created by Tanner Silva on 6/7/22.
//

#ifndef CLIBSWIFTSLASH_WC_H
#define CLIBSWIFTSLASH_WC_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

struct writerchain {
	const uint8_t*_Nonnull data;
	const size_t datasize;
	size_t written;
	struct writerchain*_Nullable next;
};

typedef struct writerchain*_Nullable chaintail;

// append data to the chain
void wc_append(chaintail*_Nonnull, const uint8_t*_Nonnull, const size_t);

// flushes as much of the chain to the file handle as possible
void wc_flush(chaintail*_Nonnull, const int, int*_Nonnull);

// deinitialize a given writerchain
void wc_close(chaintail*_Nonnull);

#endif /* CLIBSWIFTSLASH_WC_H */
