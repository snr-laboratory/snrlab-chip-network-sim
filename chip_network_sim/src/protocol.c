#include "chipsim/protocol.h"

#include <stddef.h>
#include <string.h>

const char *
chipsim_sync_mode_name(chipsim_sync_mode_t mode)
{
	switch (mode) {
	case CHIPSIM_SYNC_BARRIER_ACK:
		return "barrier_ack";
	case CHIPSIM_SYNC_PUBSUB_ONLY:
		return "pubsub_only";
	case CHIPSIM_SYNC_WINDOWED_ACK:
		return "windowed_ack";
	default:
		return "unknown";
	}
}

int
chipsim_parse_sync_mode(const char *value, chipsim_sync_mode_t *mode)
{
	if (value == NULL || mode == NULL) {
		return -1;
	}
	if (strcmp(value, "barrier_ack") == 0) {
		*mode = CHIPSIM_SYNC_BARRIER_ACK;
		return 0;
	}
	if (strcmp(value, "pubsub_only") == 0) {
		*mode = CHIPSIM_SYNC_PUBSUB_ONLY;
		return 0;
	}
	if (strcmp(value, "windowed_ack") == 0) {
		*mode = CHIPSIM_SYNC_WINDOWED_ACK;
		return 0;
	}
	return -1;
}
