#ifndef CLIBSWIFTSLASH_LP_H
#define CLIBSWIFTSLASH_LP_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

/// `usr_ptr_lp_t` defines a nullable pointer type that the user may freeply pass into the line parser. this pointer is transparently passed into the datahandler.
typedef void(^_Nonnull lp_handler_f)(const uint8_t *_Nonnull, const size_t);

/// primary lineparser structure
typedef struct lineparser {
	uint8_t*_Nullable match;
	uint8_t matchsize; //small pattern strings only.
	uint8_t matched;
	
	uint8_t *_Nonnull intakebuff;
	size_t buffsize;
	
	size_t i;
	size_t occupied;
} lineparser_t;

/// @brief initialize a line parser.
/// @param match the pattern to match against. if this is NULL, the line parser will not match against any pattern.
/// @param matchlen the length of the pattern to match against. if this is 0, the line parser will not match against any pattern.
extern lineparser_t lp_init(const uint8_t*_Nullable match, const uint8_t matchlen);

/// @brief send data into the line parser.
/// @param parser the parser to receive the data.
/// @param intake_data the data to send into the parser.
/// @param data_len the length of the data to send into the parser.
/// @param dh the data handler to call when a line is parsed.
extern void lp_intake(lineparser_t*_Nonnull parser, const uint8_t*_Nonnull intake_data, size_t data_len, const lp_handler_f dh);

/// @brief remove the lineparser from memory, firing the data handler (if necessary) to handle the remaining data in the input buffer.
/// @param parser the parser to close.
/// @param dh the data handler to call when a line is parsed.
extern void lp_close(lineparser_t*_Nonnull parser, const lp_handler_f dh);

/// @brief resize the line parser's buffer up.
/// @param parser the parser to resize.
extern void lp_close_dataloss(lineparser_t*_Nonnull parser);

#endif // CLIBSWIFTSLASH_LP_H
