#include "chipsim/fifo.h"

#include <stdlib.h>
#include <string.h>

int
chipsim_fifo_init(chipsim_fifo_t *fifo, size_t capacity)
{
	if (fifo == NULL || capacity == 0) {
		return -1;
	}
	memset(fifo, 0, sizeof(*fifo));
	fifo->items = calloc(capacity, sizeof(chipsim_packet_t));
	if (fifo->items == NULL) {
		return -1;
	}
	fifo->capacity = capacity;
	return 0;
}

void
chipsim_fifo_free(chipsim_fifo_t *fifo)
{
	if (fifo == NULL) {
		return;
	}
	free(fifo->items);
	memset(fifo, 0, sizeof(*fifo));
}

int
chipsim_fifo_push(chipsim_fifo_t *fifo, const chipsim_packet_t *packet)
{
	if (fifo == NULL || packet == NULL || fifo->items == NULL) {
		return -1;
	}
	if (fifo->size == fifo->capacity) {
		return 0;
	}
	fifo->items[fifo->tail] = *packet;
	fifo->tail              = (fifo->tail + 1u) % fifo->capacity;
	fifo->size++;
	return 1;
}

int
chipsim_fifo_pop(chipsim_fifo_t *fifo, chipsim_packet_t *packet_out)
{
	if (fifo == NULL || packet_out == NULL || fifo->items == NULL) {
		return -1;
	}
	if (fifo->size == 0) {
		return 0;
	}
	*packet_out = fifo->items[fifo->head];
	fifo->head  = (fifo->head + 1u) % fifo->capacity;
	fifo->size--;
	return 1;
}

size_t
chipsim_fifo_size(const chipsim_fifo_t *fifo)
{
	return fifo ? fifo->size : 0;
}
