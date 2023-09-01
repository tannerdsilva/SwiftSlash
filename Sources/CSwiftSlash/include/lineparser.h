#ifndef CLIBSWIFTSLASH_LP_H
#define CLIBSWIFTSLASH_LP_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

// `usr_ptr_lp_t` defines a nullable pointer type that the user may freeply pass into the line parser. this pointer is transparently passed into the datahandler.
typedef void(^_Nonnull lp_handler_f)(const uint8_t *_Nonnull, const size_t);

typedef struct lineparser {
	uint8_t*_Nullable match;
	uint8_t matchsize; //small pattern strings only.
	uint8_t matched;
	
	uint8_t *_Nonnull intakebuff;
	size_t buffsize;
	
	size_t i;
	size_t occupied;
} lineparser_t;

/// initialize a new line parser.
extern lineparser_t lp_init(const uint8_t*_Nullable match, const uint8_t matchlen);

extern void lp_intake(lineparser_t*_Nonnull parser, const uint8_t*_Nonnull intake_data, size_t data_len, const lp_handler_f dh);

// remove the lineparser from memory, firing the data handler (if necessary) to handle the remaining data in the input buffer.
extern void lp_close(lineparser_t*_Nonnull parser, const lp_handler_f dh);

// remove the lineparser from memory without handling the remaining data that was stored in the input buffer.
extern void lp_close_dataloss(lineparser_t*_Nonnull parser);
#endif
