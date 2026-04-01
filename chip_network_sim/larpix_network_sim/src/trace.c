#include "chipsim/trace.h"

#include <errno.h>
#include <string.h>

int
chipsim_trace_open(chipsim_trace_writer_t *writer, const char *path, uint32_t chip_id)
{
	chipsim_trace_header_v1_t header;

	if (writer == NULL) {
		return -1;
	}
	memset(writer, 0, sizeof(*writer));
	writer->chip_id = chip_id;

	if (path == NULL || path[0] == '\0') {
		return 0;
	}

	writer->fp = fopen(path, "wb");
	if (writer->fp == NULL) {
		fprintf(stderr, "trace[%u] open(%s) failed: %s\n", chip_id, path, strerror(errno));
		return -1;
	}
	(void) setvbuf(writer->fp, NULL, _IOFBF, 1 << 20);

	memset(&header, 0, sizeof(header));
	memcpy(header.magic, CHIPSIM_TRACE_MAGIC, sizeof(header.magic));
	header.chip_id     = chip_id;
	header.version     = CHIPSIM_TRACE_VERSION;
	header.header_size = (uint16_t) sizeof(header);
	header.record_size = (uint16_t) sizeof(chipsim_trace_row_v1_t);

	if (fwrite(&header, sizeof(header), 1, writer->fp) != 1) {
		fprintf(stderr, "trace[%u] failed to write header\n", chip_id);
		fclose(writer->fp);
		writer->fp = NULL;
		return -1;
	}

	return 0;
}

int
chipsim_trace_emit(chipsim_trace_writer_t *writer, const chipsim_trace_row_v1_t *row)
{
	if (writer == NULL || row == NULL) {
		return -1;
	}
	if (writer->fp == NULL) {
		return 0;
	}
	if (fwrite(row, sizeof(*row), 1, writer->fp) != 1) {
		fprintf(stderr, "trace[%u] failed to write row\n", writer->chip_id);
		return -1;
	}
	writer->row_count++;
	return 0;
}

int
chipsim_trace_emit_fields(chipsim_trace_writer_t *writer, uint64_t tick, uint16_t event_type,
    uint32_t fifo_occupancy, uint64_t packet_word)
{
	chipsim_trace_row_v1_t row;

	memset(&row, 0, sizeof(row));
	row.tick           = tick;
	row.event_type     = event_type;
	row.fifo_occupancy = fifo_occupancy;
	row.packet_word    = packet_word;
	return chipsim_trace_emit(writer, &row);
}

void
chipsim_trace_close(chipsim_trace_writer_t *writer)
{
	if (writer == NULL || writer->fp == NULL) {
		return;
	}
	fflush(writer->fp);
	fclose(writer->fp);
	writer->fp = NULL;
}

uint64_t
chipsim_trace_pack_packet_word(const chipsim_packet_t *packet)
{
	if (packet == NULL) {
		return 0;
	}
	return (((uint64_t) packet->src_id & 0xFFFFULL) << 48) |
	    (((uint64_t) packet->timestamp & 0xFFFFFFULL) << 24) |
	    ((uint64_t) packet->payload & 0xFFFFFFULL);
}
