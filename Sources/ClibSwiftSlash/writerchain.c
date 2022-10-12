//
//  writerchain.c.c
//  
//
//  Created by Tanner Silva on 6/7/22.
//

#include "writerchain.h"

#include <stdlib.h>
#include <string.h>
#include <stdatomic.h>
#include <unistd.h>
#include <errno.h>
#include <stdio.h>

void wc_append(chaintail *base, const uint8_t* data, const size_t datalen) {
	struct writerchain newchain = {
		.data = memcpy(malloc(datalen), data, datalen),
		.datasize = datalen,
		.next = NULL
	};
	
	if ((*base) == NULL) {
		(*base) = memcpy(malloc(sizeof newchain), &newchain, sizeof(newchain));
	} else {
		chaintail cur = (*base);
		chaintail next = (*base);
		while (next != NULL) {
			cur = next;
			next = next->next;
		}
		cur->next = memcpy(malloc(sizeof newchain), &newchain, sizeof(newchain));
	}
}


void wc_flush(chaintail *base, const int fd, int *err) {
	if ((*base) == NULL) {
		(*err) = 0;
		return;
	}
	do {
		int currentresult = 0;
		while ((*base)->written < (*base)->datasize) {
			do {
				currentresult = write(fd, (*base)->data, (*base)->datasize);
			} while ((currentresult == -1) && (errno == EAGAIN));
			if (currentresult == -1) {
				*err = errno;
				return;
			} else {
				(*base)->written += currentresult;
			}
		}
		chaintail old = (*base);
		(*base) = (*base)->next;
		free((void*)old->data);
		free(old);
	} while ((*base) != NULL);
	(*err) = 0;
	return;
}

//// deinitialize a given writerchain
void wc_close(chaintail*_Nonnull base) {
	while ((*base) != NULL) {
		chaintail old = (*base);
		(*base) = (*base)->next;
		free((void*)old->data);
		free(old);
	}
}
