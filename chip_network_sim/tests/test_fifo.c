#include <stdio.h>
#include <stdlib.h>

#include "chipsim/fifo.h"

static void
expect(int condition, const char *message)
{
	if (!condition) {
		fprintf(stderr, "FAIL: %s\n", message);
		exit(1);
	}
}

int
main(void)
{
	chipsim_fifo_t   fifo;
	chipsim_packet_t p0 = {.src_id = 1, .timestamp = 10, .payload = 0xAA, .seq_local = 0};
	chipsim_packet_t p1 = {.src_id = 2, .timestamp = 11, .payload = 0xBB, .seq_local = 1};
	chipsim_packet_t p2 = {.src_id = 3, .timestamp = 12, .payload = 0xCC, .seq_local = 2};
	chipsim_packet_t out;

	expect(chipsim_fifo_init(&fifo, 2) == 0, "init");
	expect(chipsim_fifo_push(&fifo, &p0) == 1, "push p0");
	expect(chipsim_fifo_push(&fifo, &p1) == 1, "push p1");
	expect(chipsim_fifo_push(&fifo, &p2) == 0, "push full returns 0");
	expect(chipsim_fifo_size(&fifo) == 2, "size full");

	expect(chipsim_fifo_pop(&fifo, &out) == 1, "pop p0");
	expect(out.src_id == p0.src_id, "order p0");
	expect(chipsim_fifo_pop(&fifo, &out) == 1, "pop p1");
	expect(out.src_id == p1.src_id, "order p1");
	expect(chipsim_fifo_pop(&fifo, &out) == 0, "pop empty");

	chipsim_fifo_free(&fifo);
	printf("PASS\n");
	return 0;
}
