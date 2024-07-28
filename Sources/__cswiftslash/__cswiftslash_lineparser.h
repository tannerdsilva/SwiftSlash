// LICENSE MIT
// copyright (c) tanner silva 2024. all rights reserved.
#ifndef _CSWIFTSLASH_LINEPARSER_H
#define _CSWIFTSLASH_LINEPARSER_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include "__cswiftslash_types.h"

/// `usr_ptr_lp_t` defines a nullable pointer type that the user may freeply pass into the line parser. this pointer is transparently passed into the datahandler.
typedef void(*_Nonnull _cswiftslash_lineparser_handler_f)(const uint8_t *_Nonnull, const size_t, _cswiftslash_cptr_t);

/// primary lineparser structure
typedef struct _cswiftslash_lineparser {
	uint8_t*_Nullable match;
	uint8_t matchsize; // small pattern strings only (must be no longer than 8 bit value in byte length)
	uint8_t matched;
	
	uint8_t *_Nonnull intakebuff;
	size_t buffsize;
	
	size_t i;
	size_t occupied;
} _cswiftslash_lineparser_t;

/// @brief initialize a line parser.
/// @param match the pattern to match against. if this is NULL, the line parser will not match against any pattern.
/// @param matchlen the length of the pattern to match against. if this is 0, the line parser will not match against any pattern.
_cswiftslash_lineparser_t _cswiftslash_lineparser_init(const uint8_t*_Nullable match, const uint8_t matchlen);

/// @brief prepare a line parser intake buffer to take in at most `data_len` bytes.
/// @param parser the parser to prepare.
/// @param data_len the number of bytes to prepare the buffer for.
/// @return a pointer to the buffer to write data into.
uint8_t *_Nonnull _cswiftslash_lineparser_intake_prepare(_cswiftslash_lineparser_t*_Nonnull parser, const size_t data_len);


/// @brief commits that a number of bytes have been applied to the line parser.
/// @param parser the parser to apply the data to.
/// @param data_len the number of bytes that were added to the buffer.
void _cswiftslash_lineparser_intake_apply(_cswiftslash_lineparser_t*_Nonnull parser, const size_t data_len);

/// @brief work through the bytes that were just applied to the line parser.
/// @param parser the parser to receive the data.
/// @param dh the data handler to call when a line is parsed.
/// @param dh_context the context to pass into the data handler.
void _cswiftslash_lineparser_intake_process(_cswiftslash_lineparser_t*_Nonnull parser, const _cswiftslash_lineparser_handler_f dh, _cswiftslash_cptr_t dh_context);

/// @brief remove the lineparser from memory, firing the data handler (if necessary) to handle the remaining data in the input buffer.
/// @param parser the parser to close.
/// @param dh the data handler to call when a line is parsed.
void _cswiftslash_lineparser_close(_cswiftslash_lineparser_t*_Nonnull parser, const _cswiftslash_lineparser_handler_f dh, _cswiftslash_cptr_t dh_context);

/// @brief resize the line parser's buffer up.
/// @param parser the parser to resize.
void _cswiftslash_lineparser_close_dataloss(_cswiftslash_lineparser_t*_Nonnull parser);

#endif // _CSWIFTSLASH_LINEPARSER_H
