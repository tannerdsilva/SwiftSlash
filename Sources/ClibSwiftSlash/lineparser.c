#include "lineparser.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

void lineparser_resize_up(lineparser *parser) {
	// make the new buffer with a doubled buffer size
	size_t newsize = parser->buffsize * 2;
	uint8_t *newBuf = malloc(newsize);
	
	// copy the data to the new buffer
	memcpy(newBuf, parser->intakebuff, parser->occupied);
	
	// free the old buffer from memory
	free(parser->intakebuff);
	
	// assign the new values to the parser
	parser->buffsize = newsize;
	parser->intakebuff = newBuf;
}

void lineparser_trim(lineparser *parser) {
	memcpy(parser->intakebuff, parser->intakebuff + parser->i, parser->buffsize - parser->i);
	parser->occupied = parser->occupied - parser->i;
	parser->i = 0;
}

int lp_init(lineparser *parser, uint8_t *match, uint8_t matchlen, void* usrPtr, datahandler handler) {
	parser->handler = handler;
	parser->buffsize = 512;
	parser->intakebuff = (uint8_t*)malloc(parser->buffsize);
	parser->i = 0;
	parser->occupied = 0;
	parser->usrPtr = usrPtr;
	parser->match = match;
	parser->matchsize = matchlen;
	parser->matched = 0;
}

int lp_intake(lineparser *parser, const uint8_t *intake_data, size_t data_len) {
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
				parser->handler(parser->intakebuff, parser->i - parser->matchsize, parser->usrPtr);
				lineparser_trim(parser);
			} else {
				parser->i = parser->i + 1;
			}
		} else {
			parser->i = parser->i + 1;
			parser->matched = 0;
		}
	}
}

void lp_close(struct lineparser *parser) {
	if (parser->occupied > 0) {
		parser->handler(parser->intakebuff, parser->occupied, parser->usrPtr);
	}
	free(parser->intakebuff);
}
