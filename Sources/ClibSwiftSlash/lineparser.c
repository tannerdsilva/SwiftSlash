#include "lineparser.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

void lineparser_resize_up(lineparser_t *parser) {
	parser->buffsize = parser->buffsize * 2;
	
	// make the new buffer with a doubled buffer size
	uint8_t *newBuf = malloc(parser->buffsize);
	
	// copy the data to the new buffer
	memcpy(newBuf, parser->intakebuff, parser->occupied);
	
	free(parser->intakebuff);
	
	// assign the new values to the parser
	parser->intakebuff = newBuf;
}

// prepares the line parser to parse the next line. clears the previous line from the buffer
void lineparser_trim(lineparser_t *parser) {
	memcpy(parser->intakebuff, parser->intakebuff + parser->i, parser->buffsize - parser->i);
	parser->occupied = parser->occupied - parser->i;
	parser->i = 0;
}

// initialize a line parser
extern lineparser_t*_Nonnull lp_init(const uint8_t*_Nullable match, const uint8_t matchlen) {
	lineparser_t *parser = malloc(sizeof(lineparser_t));
	parser->buffsize = 512;
	parser->intakebuff = (uint8_t*)malloc(parser->buffsize);
	parser->i = 0;
	parser->occupied = 0;
	if (matchlen > 0) {
		parser->match = (uint8_t*)malloc(matchlen);
		memcpy(parser->match, match, matchlen);
	}
	parser->matchsize = matchlen;
	parser->matched = 0;
	return parser;
}

// send data into the line parser
void lp_intake(lineparser_t*_Nonnull parser, const uint8_t*_Nonnull intake_data, size_t data_len, const usr_ptr_t usrPtr, datahandler dh) {
	// resize the parser to fit the data, if necessary
	while ((parser->occupied + data_len) > parser->buffsize) {
		lineparser_resize_up(parser);
	}
	
	// install the data in the intake buffer
	memcpy(parser->intakebuff + parser->occupied, intake_data, data_len);
	parser->occupied = parser->occupied + data_len;
	
	while (parser->i < parser->occupied) {
		if (parser->matchsize > 0) {
			if (parser->match[parser->matched] == parser->intakebuff[parser->i]) {
				parser->matched = parser->matched + 1;
				if (parser->matchsize == parser->matched) {
					parser->matched = 0;
					parser->i = parser->i + 1;
					dh(parser->intakebuff, parser->i - parser->matchsize, usrPtr);
					lineparser_trim(parser);
				} else {
					parser->i = parser->i + 1;
				}
			} else {
				parser->i = parser->i + 1;
				parser->matched = 0;
			}
		} else {
			dh(intake_data, data_len, usrPtr);
		}
	}
}

// close the line parser from memory
void lp_close(lineparser_t*_Nonnull parser, usr_ptr_t usrPtr, datahandler dh) {
	if (parser->occupied > 0) {
		dh(parser->intakebuff, parser->occupied, usrPtr);
	}
	free(parser->intakebuff);
	if (parser->matchsize > 0) {
		free(parser->match);
	}
	free(parser);
}
