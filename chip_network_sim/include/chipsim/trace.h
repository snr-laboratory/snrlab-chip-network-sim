#ifndef CHIPSIM_TRACE_H
#define CHIPSIM_TRACE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

#include "chipsim/protocol.h"

#ifdef __cplusplus
extern "C" {
#endif

#define CHIPSIM_TRACE_MAGIC "CTRACE01"
#define CHIPSIM_TRACE_VERSION 1u

typedef enum {
	CHIPSIM_TRACE_EVT_GEN_LOCAL = 1,
	CHIPSIM_TRACE_EVT_ENQ_LOCAL_OK = 2,
	CHIPSIM_TRACE_EVT_ENQ_LOCAL_DROP_FULL = 3,
	CHIPSIM_TRACE_EVT_ENQ_NEIGH_OK = 4,
	CHIPSIM_TRACE_EVT_ENQ_NEIGH_DROP_FULL = 5,
	CHIPSIM_TRACE_EVT_DEQ_OUT = 6
} chipsim_trace_event_t;

typedef struct {
	uint8_t  magic[8];
	uint32_t chip_id;
	uint16_t version;
	uint16_t header_size;
	uint16_t record_size;
	uint16_t reserved0;
	uint8_t  reserved1[44];
} chipsim_trace_header_v1_t;

typedef struct {
	uint64_t tick;
	uint16_t event_type;
	uint16_t reserved0;
	uint32_t fifo_occupancy;
	uint64_t packet_word; // Keep packet_word at tail for forward extension.
} chipsim_trace_row_v1_t;

typedef struct {
	FILE    *fp;
	uint64_t row_count;
	uint32_t chip_id;
} chipsim_trace_writer_t;

int  chipsim_trace_open(chipsim_trace_writer_t *writer, const char *path, uint32_t chip_id);
int  chipsim_trace_emit(chipsim_trace_writer_t *writer, const chipsim_trace_row_v1_t *row);
int  chipsim_trace_emit_fields(chipsim_trace_writer_t *writer, uint64_t tick, uint16_t event_type,
     uint32_t fifo_occupancy, uint64_t packet_word);
void chipsim_trace_close(chipsim_trace_writer_t *writer);
bool chipsim_trace_is_enabled(const chipsim_trace_writer_t *writer);

uint64_t chipsim_trace_pack_packet_word(const chipsim_packet_t *packet);

#ifdef __cplusplus
}
#endif

#if defined(__cplusplus)
static_assert(sizeof(chipsim_trace_header_v1_t) == 64, "trace header must be 64 bytes");
static_assert(sizeof(chipsim_trace_row_v1_t) == 24, "trace row v1 must be 24 bytes");
#else
_Static_assert(sizeof(chipsim_trace_header_v1_t) == 64, "trace header must be 64 bytes");
_Static_assert(sizeof(chipsim_trace_row_v1_t) == 24, "trace row v1 must be 24 bytes");
#endif

#endif
