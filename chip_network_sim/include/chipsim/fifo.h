#ifndef CHIPSIM_FIFO_H
#define CHIPSIM_FIFO_H

#include <stddef.h>

#include "chipsim/protocol.h"

typedef struct {
	chipsim_packet_t *items;
	size_t            capacity;
	size_t            head;
	size_t            tail;
	size_t            size;
} chipsim_fifo_t;

int    chipsim_fifo_init(chipsim_fifo_t *fifo, size_t capacity);
void   chipsim_fifo_free(chipsim_fifo_t *fifo);
int    chipsim_fifo_push(chipsim_fifo_t *fifo, const chipsim_packet_t *packet);
int    chipsim_fifo_pop(chipsim_fifo_t *fifo, chipsim_packet_t *packet_out);
size_t chipsim_fifo_size(const chipsim_fifo_t *fifo);

#endif
