#ifndef CLIBSWIFTSLASH_LP_H
#define CLIBSWIFTSLASH_LP_H

#include <unistd.h>

/*enum lineparse_mode {
	cr,
	lf,
	crlf,
	none
};*/

typedef void(*datahandler)(const uint8_t *, size_t, void*);

typedef struct lineparser {
//	enum lineparse_mode mode;
	void* usrPtr;
	
	datahandler handler;
	
	uint8_t *match;
	uint8_t matchsize; //small pattern strings only.
	uint8_t matched;
	
	uint8_t *intakebuff;
	size_t buffsize;
	
	size_t i;
	size_t occupied;
	
} lineparser;


extern int lp_init(lineparser *parser, uint8_t *match, uint8_t matchlen, void* usrPtr, datahandler);
extern int lp_intake(lineparser *parser, const uint8_t *intake_data, size_t data_len);
extern void lp_close(lineparser *parser);

#endif
