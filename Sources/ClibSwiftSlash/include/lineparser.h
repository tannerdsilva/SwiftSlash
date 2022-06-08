#ifndef CLIBSWIFTSLASH_LP_H
#define CLIBSWIFTSLASH_LP_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

// `usr_ptr_t` defines a nullable pointer type that the user may freeply pass into the line parser. this pointer is transparently passed into the datahandler.
typedef void*_Nullable usr_ptr_t;
typedef void(*_Nonnull datahandler)(const uint8_t *_Nonnull, const size_t, usr_ptr_t);

typedef struct lineparser {
	uint8_t*_Nullable match;
	uint8_t matchsize; //small pattern strings only.
	uint8_t matched;
	
	uint8_t *_Nonnull intakebuff;
	size_t buffsize;
	
	size_t i;
	size_t occupied;
	
} lineparser_t;

extern lineparser_t*_Nonnull lp_init(const uint8_t*_Nullable match, const uint8_t matchlen);
extern void lp_intake(lineparser_t*_Nonnull parser, const uint8_t*_Nonnull intake_data, size_t data_len, const usr_ptr_t usrPtr, datahandler dh);
extern void lp_close(lineparser_t*_Nonnull parser, usr_ptr_t usrPtr, datahandler dh);

#endif
