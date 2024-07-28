// LICENSE MIT
// copyright (c) tanner silva 2024. all rights reserved.
#include "__cswiftslash_lineparser.h"
#include <stdlib.h>
#include <string.h>

/// line parsers may only scale in one direction. this function doubles the size of the buffer so that additional data may be stored.
/// parameters:
/// 	- parser: the line parser to resize
void lineparser_resize_up(_cswiftslash_lineparser_t *parser) {
	// double the size of the buffer
	parser->buffsize = parser->buffsize * 2;
	// call realloc to resize the buffer
	parser->intakebuff = realloc(parser->intakebuff, parser->buffsize);
}

/// @brief prepares the line parser to parse the next line. clears the previous line from the buffer.
/// @param parser the line parser to trim
void _cswiftslash_lineparser_trim(_cswiftslash_lineparser_t *parser) {
	// copy the data to the beginning of the buffer.
	memcpy(parser->intakebuff, parser->intakebuff + parser->i, parser->buffsize - parser->i);
	parser->occupied = parser->occupied - parser->i;
	parser->i = 0;
}

_cswiftslash_lineparser_t _cswiftslash_lineparser_init(const uint8_t*_Nullable match, const uint8_t matchlen) {
	_cswiftslash_lineparser_t newparser = {
		.buffsize = 1024,
		.intakebuff = malloc(1024),
		.i = 0,
		.occupied = 0,
		.matchsize = matchlen,
		.matched = 0
	};
	if (newparser.matchsize > 0) {
		newparser.match = memcpy(malloc(matchlen), match, matchlen);
	}
	return newparser;
}

uint8_t *_Nonnull _cswiftslash_lineparser_intake_prepare(_cswiftslash_lineparser_t*_Nonnull parser, const size_t data_len) {
	// resize the parser to fit the data, if necessary
	while ((parser->occupied + data_len) > parser->buffsize) {
		lineparser_resize_up(parser);
	}
	
	// return the buffer to write data into
	return parser->intakebuff + parser->occupied;
}

void _cswiftslash_lineparser_intake_apply(_cswiftslash_lineparser_t*_Nonnull parser, const size_t data_len) {
	parser->occupied = parser->occupied + data_len;
}

// send data into the line parser
void _cswiftslash_lineparser_intake_process(_cswiftslash_lineparser_t*_Nonnull parser, const _cswiftslash_lineparser_handler_f dh, _cswiftslash_cptr_t dh_context) {
	if (parser->matchsize > 0) {
		while (parser->i < parser->occupied) {
			if (parser->match[parser->matched] == parser->intakebuff[parser->i]) {
				parser->matched = parser->matched + 1;
				if (parser->matchsize == parser->matched) {
					parser->matched = 0;
					parser->i = parser->i + 1;
					dh(parser->intakebuff, parser->i - parser->matchsize, dh_context);
					_cswiftslash_lineparser_trim(parser);
				} else {
					parser->i = parser->i + 1;
				}
			} else {
				parser->i = parser->i + 1;
				parser->matched = 0;
			}
		}
	} else {
		dh(parser->intakebuff, parser->occupied, dh_context);
	}
}

// close the line parser from memory
void _cswiftslash_lineparser_close(_cswiftslash_lineparser_t*_Nonnull parser, const _cswiftslash_lineparser_handler_f dh, _cswiftslash_cptr_t dh_context) {
	if (parser->occupied > 0) {
		dh(parser->intakebuff, parser->occupied, dh_context);
	}
	free(parser->intakebuff);
	if (parser->matchsize > 0) {
		free(parser->match);
	}
}

void _cswiftslash_lineparser_close_dataloss(_cswiftslash_lineparser_t*_Nonnull parser) {
	free(parser->intakebuff);
	if (parser->matchsize > 0) {
		free(parser->match);
	}
}
