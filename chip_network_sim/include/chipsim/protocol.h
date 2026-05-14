#ifndef CHIPSIM_PROTOCOL_H
#define CHIPSIM_PROTOCOL_H

#include <stdint.h>

#define CHIPSIM_MSG_TICK 1u
#define CHIPSIM_MSG_STOP 2u
#define CHIPSIM_MSG_DONE 3u
#define CHIPSIM_MSG_METRIC 4u
#define CHIPSIM_MSG_DATA_PULL 5u
#define CHIPSIM_MSG_DATA_REPLY 6u

typedef struct {
	uint32_t src_id;
	uint64_t timestamp;
	uint32_t payload;
	uint64_t seq_local;
} chipsim_packet_t;

typedef struct {
	uint8_t  type;
	uint8_t  reserved0[3];
	uint32_t requester_id;
	uint64_t seq;
} chipsim_data_pull_msg_t;

typedef struct {
	uint8_t         type;
	uint8_t         has_packet;
	uint8_t         reserved0[2];
	uint32_t        responder_id;
	uint64_t        seq;
	chipsim_packet_t packet;
} chipsim_data_reply_msg_t;

typedef struct {
	uint8_t  type;
	uint8_t  reserved[7];
	uint64_t seq;
} chipsim_tick_msg_t;

typedef struct {
	uint8_t  type;
	uint8_t  reserved0[3];
	uint32_t chip_id;
	uint32_t reserved1;
	uint64_t seq;
	uint64_t tx_count;
	uint64_t rx_count;
	uint64_t local_gen_count;
	uint64_t drop_count;
	uint64_t fifo_occupancy;
} chipsim_done_msg_t;

typedef struct {
	uint8_t  type;
	uint8_t  reserved0[3];
	uint32_t chip_id;
	uint32_t reserved1;
	uint64_t seq;
	uint64_t tx_count;
	uint64_t rx_count;
	uint64_t local_gen_count;
	uint64_t drop_count;
	uint64_t fifo_occupancy;
	uint64_t fifo_peak;
} chipsim_metric_msg_t;

#endif
