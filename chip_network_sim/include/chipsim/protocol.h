#ifndef CHIPSIM_PROTOCOL_H
#define CHIPSIM_PROTOCOL_H

#include <stdint.h>

#define CHIPSIM_MSG_TICK 1u
#define CHIPSIM_MSG_STOP 2u
#define CHIPSIM_MSG_DONE 3u
#define CHIPSIM_MSG_METRIC 4u

typedef enum {
	CHIPSIM_SYNC_BARRIER_ACK = 0,
	CHIPSIM_SYNC_PUBSUB_ONLY = 1,
	CHIPSIM_SYNC_WINDOWED_ACK = 2
} chipsim_sync_mode_t;

typedef struct {
	uint32_t src_id;
	uint64_t timestamp;
	uint32_t payload;
	uint64_t seq_local;
} chipsim_packet_t;

typedef struct {
	uint32_t         topic;
	chipsim_packet_t packet;
} chipsim_data_msg_t;

typedef struct {
	uint8_t  type;
	uint8_t  sync_mode;
	uint16_t reserved;
	uint64_t seq;
} chipsim_tick_msg_t;

typedef struct {
	uint8_t  type;
	uint8_t  sync_mode;
	uint16_t reserved;
	uint32_t chip_id;
	uint32_t reserved2;
	uint64_t seq;
	uint64_t tx_count;
	uint64_t rx_count;
	uint64_t local_gen_count;
	uint64_t drop_count;
	uint64_t fifo_occupancy;
} chipsim_done_msg_t;

typedef struct {
	uint8_t  type;
	uint8_t  sync_mode;
	uint16_t reserved;
	uint32_t chip_id;
	uint32_t reserved2;
	uint64_t seq;
	uint64_t tx_count;
	uint64_t rx_count;
	uint64_t local_gen_count;
	uint64_t drop_count;
	uint64_t fifo_occupancy;
	uint64_t fifo_peak;
} chipsim_metric_msg_t;

const char *chipsim_sync_mode_name(chipsim_sync_mode_t mode);
int         chipsim_parse_sync_mode(const char *value, chipsim_sync_mode_t *mode);

#endif
