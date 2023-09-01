#include "include/lineparser.h"
#include <stdlib.h>
#include <string.h>

/// line parsers may only scale in one direction. this function doubles the size of the buffer so that additional data may be stored.
/// parameters:
/// 	- parser: the line parser to resize
void lineparser_resize_up(lineparser_t *parser) {
	// double the size of the buffer
	parser->buffsize = parser->buffsize * 2;

	// capture the old buffer so it may be freed
	void *oldbuff = parser->intakebuff;
	
	// copy the data to the new buffer
	parser->intakebuff = memcpy(malloc(parser->buffsize), parser->intakebuff, parser->occupied);
	
	// free the old buffer.
	free(oldbuff);
}

/// prepares the line parser to parse the next line. clears the previous line from the buffer.
/// parameters:
/// 	- parser: the line parser to trim
void lineparser_trim(lineparser_t *parser) {
	// copy the data to the beginning of the buffer.
	memcpy(parser->intakebuff, parser->intakebuff + parser->i, parser->buffsize - parser->i);
	parser->occupied = parser->occupied - parser->i;
	parser->i = 0;
}

/// initialize a line parser
/// parameters:
/// 	- match: the pattern to match against. if this is NULL, the line parser will not match against any pattern.
/// 	- matchlen: the length of the pattern to match against. if this is 0, the line parser will not match against any pattern.
extern lineparser_t lp_init(const uint8_t*_Nullable match, const uint8_t matchlen) {
	lineparser_t newparser = {
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

// send data into the line parser
void lp_intake(lineparser_t*_Nonnull parser, const uint8_t*_Nonnull intake_data, size_t data_len, const lp_handler_f dh) {
	if (parser->matchsize > 0) {
		// resize the parser to fit the data, if necessary
		while ((parser->occupied + data_len) > parser->buffsize) {
			lineparser_resize_up(parser);
		}
		
		// install the data in the intake buffer
		memcpy(parser->intakebuff + parser->occupied, intake_data, data_len);
		parser->occupied = parser->occupied + data_len;
		
		while (parser->i < parser->occupied) {
			if (parser->match[parser->matched] == parser->intakebuff[parser->i]) {
				parser->matched = parser->matched + 1;
				if (parser->matchsize == parser->matched) {
					parser->matched = 0;
					parser->i = parser->i + 1;
					dh(parser->intakebuff, parser->i - parser->matchsize);
					lineparser_trim(parser);
				} else {
					parser->i = parser->i + 1;
				}
			} else {
				parser->i = parser->i + 1;
				parser->matched = 0;
			}
		}
	} else {
		dh(intake_data, data_len);
	}
}

// close the line parser from memory
void lp_close(lineparser_t*_Nonnull parser, const lp_handler_f dh) {
	if (parser->occupied > 0) {
		dh(parser->intakebuff, parser->occupied);
	}
	free(parser->intakebuff);
	if (parser->matchsize > 0) {
		free(parser->match);
	}
}

void lp_close_dataloss(lineparser_t*_Nonnull parser) {
	free(parser->intakebuff);
	if (parser->matchsize > 0) {
		free(parser->match);
	}
}