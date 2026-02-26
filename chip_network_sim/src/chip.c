#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <inttypes.h>
#include <nng/nng.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "chipsim/fifo.h"
#include "chipsim/protocol.h"

#define CHIPSIM_DEFAULT_CLOCK_URL "tcp://127.0.0.1:23000"
#define CHIPSIM_DEFAULT_DONE_URL "tcp://127.0.0.1:23001"
#define CHIPSIM_DEFAULT_METRIC_URL "tcp://127.0.0.1:23002"
#define CHIPSIM_DEFAULT_DATA_PREFIX "tcp://127.0.0.1:%d"

typedef struct {
	int                 id;
	int                 input_id;
	int                 out_id;
	int                 ack_window;
	int                 fifo_depth;
	int                 data_port_base;
	uint32_t            seed;
	int                 gen_ppm;
	chipsim_sync_mode_t sync_mode;
	const char         *clock_url;
	const char         *done_url;
	const char         *metric_url;
	const char         *data_prefix;
} chip_options_t;

typedef struct {
	uint64_t tx_count;
	uint64_t rx_count;
	uint64_t local_gen_count;
	uint64_t drop_count;
	uint64_t fifo_peak;
	uint64_t last_seq;
} chip_metrics_t;

static void
usage(const char *prog)
{
	fprintf(stderr,
	    "Usage: %s -id <chip_id> -input <chip_id|-1> -out <chip_id|-1> "
	    "-sync <barrier_ack|pubsub_only|windowed_ack> [options]\n"
	    "Options:\n"
	    "  -ack_window <N>    window size for windowed_ack (default 4)\n"
	    "  -fifo_depth <N>    local FIFO depth (default 32)\n"
	    "  -gen_ppm <N>       local generation rate per tick in ppm [0..1e6] "
	    "(default 100000)\n"
	    "  -seed <N>          RNG seed (default 1)\n"
	    "  -clock_url <URI>   orchestrator tick endpoint\n"
	    "  -done_url <URI>    orchestrator done endpoint\n"
	    "  -metric_url <URI>  orchestrator metric endpoint\n"
	    "  -data_prefix <URI> per-chip data endpoint prefix or printf pattern\n"
	    "  -data_port_base <N> numeric base added to chip id when using %%d pattern\n",
	    prog);
}

static int
parse_int(const char *value, int *out)
{
	long v;
	char *end;

	errno = 0;
	v     = strtol(value, &end, 10);
	if (errno != 0 || end == value || *end != '\0') {
		return -1;
	}
	if (v < INT32_MIN || v > INT32_MAX) {
		return -1;
	}
	*out = (int) v;
	return 0;
}

static int
parse_u32(const char *value, uint32_t *out)
{
	unsigned long v;
	char         *end;

	errno = 0;
	v     = strtoul(value, &end, 10);
	if (errno != 0 || end == value || *end != '\0' || v > UINT32_MAX) {
		return -1;
	}
	*out = (uint32_t) v;
	return 0;
}

static int
parse_args(int argc, char **argv, chip_options_t *opts)
{
	int i;

	memset(opts, 0, sizeof(*opts));
	opts->id         = -1;
	opts->input_id   = -1;
	opts->out_id     = -1;
	opts->ack_window = 4;
	opts->fifo_depth = 32;
	opts->data_port_base = 0;
	opts->seed       = 1u;
	opts->gen_ppm    = 100000;
	opts->sync_mode  = CHIPSIM_SYNC_BARRIER_ACK;
	opts->clock_url  = CHIPSIM_DEFAULT_CLOCK_URL;
	opts->done_url   = CHIPSIM_DEFAULT_DONE_URL;
	opts->metric_url = CHIPSIM_DEFAULT_METRIC_URL;
	opts->data_prefix = CHIPSIM_DEFAULT_DATA_PREFIX;

	for (i = 1; i < argc; i++) {
		if (strcmp(argv[i], "-id") == 0 && i + 1 < argc) {
			if (parse_int(argv[++i], &opts->id) != 0) {
				return -1;
			}
		} else if (strcmp(argv[i], "-input") == 0 && i + 1 < argc) {
			if (parse_int(argv[++i], &opts->input_id) != 0) {
				return -1;
			}
		} else if (strcmp(argv[i], "-out") == 0 && i + 1 < argc) {
			if (parse_int(argv[++i], &opts->out_id) != 0) {
				return -1;
			}
		} else if (strcmp(argv[i], "-sync") == 0 && i + 1 < argc) {
			if (chipsim_parse_sync_mode(argv[++i], &opts->sync_mode) != 0) {
				return -1;
			}
		} else if (strcmp(argv[i], "-ack_window") == 0 && i + 1 < argc) {
			if (parse_int(argv[++i], &opts->ack_window) != 0 || opts->ack_window <= 0) {
				return -1;
			}
		} else if (strcmp(argv[i], "-fifo_depth") == 0 && i + 1 < argc) {
			if (parse_int(argv[++i], &opts->fifo_depth) != 0 || opts->fifo_depth <= 0) {
				return -1;
			}
		} else if (strcmp(argv[i], "-gen_ppm") == 0 && i + 1 < argc) {
			if (parse_int(argv[++i], &opts->gen_ppm) != 0 || opts->gen_ppm < 0 ||
			    opts->gen_ppm > 1000000) {
				return -1;
			}
		} else if (strcmp(argv[i], "-seed") == 0 && i + 1 < argc) {
			if (parse_u32(argv[++i], &opts->seed) != 0) {
				return -1;
			}
		} else if (strcmp(argv[i], "-clock_url") == 0 && i + 1 < argc) {
			opts->clock_url = argv[++i];
		} else if (strcmp(argv[i], "-done_url") == 0 && i + 1 < argc) {
			opts->done_url = argv[++i];
		} else if (strcmp(argv[i], "-metric_url") == 0 && i + 1 < argc) {
			opts->metric_url = argv[++i];
		} else if (strcmp(argv[i], "-data_prefix") == 0 && i + 1 < argc) {
			opts->data_prefix = argv[++i];
		} else if (strcmp(argv[i], "-data_port_base") == 0 && i + 1 < argc) {
			if (parse_int(argv[++i], &opts->data_port_base) != 0 || opts->data_port_base < 0 ||
			    opts->data_port_base > 65535) {
				return -1;
			}
		} else {
			return -1;
		}
	}

	if (opts->id < 0) {
		return -1;
	}
	return 0;
}

static int
build_data_url(
    char *dst, size_t dst_len, const char *prefix, int chip_id, int data_port_base)
{
	int n;

	if (strstr(prefix, "%d") != NULL) {
		n = snprintf(dst, dst_len, prefix, data_port_base + chip_id);
	} else {
		n = snprintf(dst, dst_len, "%s%d", prefix, chip_id);
	}
	if (n < 0 || (size_t) n >= dst_len) {
		return -1;
	}
	return 0;
}

static uint32_t
xorshift32(uint32_t *state)
{
	uint32_t x = *state;
	x ^= x << 13;
	x ^= x >> 17;
	x ^= x << 5;
	*state = x;
	return x;
}

static int
should_send_done(const chip_options_t *opts, uint64_t seq)
{
	if (opts->sync_mode == CHIPSIM_SYNC_BARRIER_ACK) {
		return 1;
	}
	if (opts->sync_mode == CHIPSIM_SYNC_WINDOWED_ACK) {
		return ((seq + 1u) % (uint64_t) opts->ack_window) == 0u;
	}
	return 0;
}

static int
send_done(nng_socket done_push, const chip_options_t *opts, uint64_t seq, size_t fifo_occupancy,
    const chip_metrics_t *metrics)
{
	chipsim_done_msg_t done;
	int                rv;

	memset(&done, 0, sizeof(done));
	done.type           = CHIPSIM_MSG_DONE;
	done.sync_mode      = (uint8_t) opts->sync_mode;
	done.chip_id        = (uint32_t) opts->id;
	done.seq            = seq;
	done.tx_count       = metrics->tx_count;
	done.rx_count       = metrics->rx_count;
	done.local_gen_count = metrics->local_gen_count;
	done.drop_count     = metrics->drop_count;
	done.fifo_occupancy = (uint64_t) fifo_occupancy;

	rv = nng_send(done_push, &done, sizeof(done), 0);
	if (rv != 0) {
		fprintf(stderr, "chip[%d] failed to send DONE: %s\n", opts->id, nng_strerror(rv));
		return -1;
	}
	return 0;
}

static int
send_metric(nng_socket metric_push, const chip_options_t *opts, size_t fifo_occupancy,
    const chip_metrics_t *metrics)
{
	chipsim_metric_msg_t m;
	int                  rv;

	memset(&m, 0, sizeof(m));
	m.type            = CHIPSIM_MSG_METRIC;
	m.sync_mode       = (uint8_t) opts->sync_mode;
	m.chip_id         = (uint32_t) opts->id;
	m.seq             = metrics->last_seq;
	m.tx_count        = metrics->tx_count;
	m.rx_count        = metrics->rx_count;
	m.local_gen_count = metrics->local_gen_count;
	m.drop_count      = metrics->drop_count;
	m.fifo_occupancy  = (uint64_t) fifo_occupancy;
	m.fifo_peak       = metrics->fifo_peak;

	rv = nng_send(metric_push, &m, sizeof(m), 0);
	if (rv != 0) {
		fprintf(stderr, "chip[%d] failed to send METRIC: %s\n", opts->id, nng_strerror(rv));
		return -1;
	}
	return 0;
}

int
main(int argc, char **argv)
{
	chip_options_t opts;
	chipsim_fifo_t fifo;
	chip_metrics_t metrics;
	nng_socket     clock_sub  = NNG_SOCKET_INITIALIZER;
	nng_socket     data_pub   = NNG_SOCKET_INITIALIZER;
	nng_socket     data_sub   = NNG_SOCKET_INITIALIZER;
	nng_socket     done_push  = NNG_SOCKET_INITIALIZER;
	nng_socket     metric_push = NNG_SOCKET_INITIALIZER;
	char           my_data_url[256];
	char           input_data_url[256];
	uint32_t       rng_state;
	int            rv;
	bool           has_input;
	nng_err        init_err;

	init_err = nng_init(NULL);
	if (init_err != 0) {
		fprintf(stderr, "chip nng_init failed: %s\n", nng_strerror((int) init_err));
		return 1;
	}

	if (parse_args(argc, argv, &opts) != 0) {
		usage(argv[0]);
		return 2;
	}
	has_input = opts.input_id >= 0;
	memset(&metrics, 0, sizeof(metrics));

	if (build_data_url(
	        my_data_url, sizeof(my_data_url), opts.data_prefix, opts.id, opts.data_port_base) != 0) {
		fprintf(stderr, "chip[%d] invalid data prefix\n", opts.id);
		return 1;
	}
	if (has_input && build_data_url(input_data_url, sizeof(input_data_url), opts.data_prefix,
	                     opts.input_id, opts.data_port_base) != 0) {
		fprintf(stderr, "chip[%d] invalid data prefix for input\n", opts.id);
		return 1;
	}
	if (chipsim_fifo_init(&fifo, (size_t) opts.fifo_depth) != 0) {
		fprintf(stderr, "chip[%d] failed to init FIFO\n", opts.id);
		return 1;
	}

	rv = nng_sub0_open(&clock_sub);
	if (rv != 0) {
		fprintf(stderr, "chip[%d] nng_sub0_open(clock) failed: %s\n", opts.id, nng_strerror(rv));
		goto fail;
	}
	rv = nng_sub0_socket_subscribe(clock_sub, NULL, 0);
	if (rv != 0) {
		fprintf(stderr, "chip[%d] subscribe(clock) failed: %s\n", opts.id, nng_strerror(rv));
		goto fail;
	}
	rv = nng_dial(clock_sub, opts.clock_url, NULL, 0);
	if (rv != 0) {
		fprintf(stderr, "chip[%d] dial(clock) failed: %s\n", opts.id, nng_strerror(rv));
		goto fail;
	}

	rv = nng_pub0_open(&data_pub);
	if (rv != 0) {
		fprintf(stderr, "chip[%d] nng_pub0_open(data_pub) failed: %s\n", opts.id, nng_strerror(rv));
		goto fail;
	}
	rv = nng_listen(data_pub, my_data_url, NULL, 0);
	if (rv != 0) {
		fprintf(stderr, "chip[%d] listen(data_pub) failed at %s: %s\n", opts.id, my_data_url,
		    nng_strerror(rv));
		goto fail;
	}

	if (has_input) {
		uint32_t topic = (uint32_t) opts.input_id;
		rv             = nng_sub0_open(&data_sub);
		if (rv != 0) {
			fprintf(stderr, "chip[%d] nng_sub0_open(data_sub) failed: %s\n", opts.id,
			    nng_strerror(rv));
			goto fail;
		}
		rv = nng_sub0_socket_subscribe(data_sub, &topic, sizeof(topic));
		if (rv != 0) {
			fprintf(stderr, "chip[%d] subscribe(data_sub) failed: %s\n", opts.id,
			    nng_strerror(rv));
			goto fail;
		}
		rv = nng_dial(data_sub, input_data_url, NULL, 0);
		if (rv != 0) {
			fprintf(stderr, "chip[%d] dial(data_sub) failed at %s: %s\n", opts.id,
			    input_data_url, nng_strerror(rv));
			goto fail;
		}
	}

	if (opts.sync_mode != CHIPSIM_SYNC_PUBSUB_ONLY) {
		rv = nng_push0_open(&done_push);
		if (rv != 0) {
			fprintf(stderr, "chip[%d] nng_push0_open(done) failed: %s\n", opts.id,
			    nng_strerror(rv));
			goto fail;
		}
		rv = nng_dial(done_push, opts.done_url, NULL, 0);
		if (rv != 0) {
			fprintf(stderr, "chip[%d] dial(done) failed: %s\n", opts.id, nng_strerror(rv));
			goto fail;
		}
	}

	rv = nng_push0_open(&metric_push);
	if (rv != 0) {
		fprintf(stderr, "chip[%d] nng_push0_open(metric) failed: %s\n", opts.id, nng_strerror(rv));
		goto fail;
	}
	rv = nng_dial(metric_push, opts.metric_url, NULL, 0);
	if (rv != 0) {
		fprintf(stderr, "chip[%d] dial(metric) failed: %s\n", opts.id, nng_strerror(rv));
		goto fail;
	}

	rng_state = opts.seed ^ ((uint32_t) opts.id * 2654435761u);
	for (;;) {
		chipsim_tick_msg_t tick;
		size_t             tick_sz = sizeof(tick);
		chipsim_packet_t   local_packet;
		chipsim_packet_t   neighbor_packet;
		chipsim_packet_t   out_packet;
		bool               have_local    = false;
		bool               have_neighbor = false;
		size_t             occupancy;
		uint32_t           draw;

		rv = nng_recv(clock_sub, &tick, &tick_sz, 0);
		if (rv != 0) {
			fprintf(stderr, "chip[%d] recv(clock) failed: %s\n", opts.id, nng_strerror(rv));
			goto fail;
		}
		if (tick_sz != sizeof(tick)) {
			continue;
		}
		metrics.last_seq = tick.seq;
		if (tick.type == CHIPSIM_MSG_STOP) {
			break;
		}
		if (tick.type != CHIPSIM_MSG_TICK) {
			continue;
		}

		if (has_input) {
			chipsim_data_msg_t msg;
			size_t             msg_sz = sizeof(msg);
			rv                        = nng_recv(data_sub, &msg, &msg_sz, NNG_FLAG_NONBLOCK);
			if (rv == 0 && msg_sz == sizeof(msg)) {
				neighbor_packet = msg.packet;
				have_neighbor   = true;
				metrics.rx_count++;
			} else if (rv != NNG_EAGAIN && rv != NNG_ETIMEDOUT) {
				fprintf(stderr, "chip[%d] recv(data_sub) failed: %s\n", opts.id,
				    nng_strerror(rv));
			}
		}

		draw = xorshift32(&rng_state) % 1000000u;
		if (draw < (uint32_t) opts.gen_ppm) {
			local_packet.src_id    = (uint32_t) opts.id;
			local_packet.timestamp = tick.seq;
			local_packet.payload   = xorshift32(&rng_state) & 0x00FFFFFFu;
			local_packet.seq_local = metrics.local_gen_count;
			have_local             = true;
			metrics.local_gen_count++;
		}

		if (chipsim_fifo_pop(&fifo, &out_packet) > 0) {
			if (opts.out_id >= 0) {
				chipsim_data_msg_t tx_msg;
				size_t             tx_sz = sizeof(tx_msg);

				tx_msg.topic  = (uint32_t) opts.id;
				tx_msg.packet = out_packet;
				rv            = nng_send(data_pub, &tx_msg, tx_sz, 0);
				if (rv != 0) {
					fprintf(stderr, "chip[%d] send(data_pub) failed: %s\n", opts.id,
					    nng_strerror(rv));
				} else {
					metrics.tx_count++;
				}
			}
		}

		// Local data has strict priority over neighbor data when both are available.
		if (have_local) {
			if (chipsim_fifo_push(&fifo, &local_packet) <= 0) {
				metrics.drop_count++;
			}
		}
		if (have_neighbor) {
			if (chipsim_fifo_push(&fifo, &neighbor_packet) <= 0) {
				metrics.drop_count++;
			}
		}

		occupancy = chipsim_fifo_size(&fifo);
		if (occupancy > metrics.fifo_peak) {
			metrics.fifo_peak = occupancy;
		}
		if (should_send_done(&opts, tick.seq) && opts.sync_mode != CHIPSIM_SYNC_PUBSUB_ONLY) {
			if (send_done(done_push, &opts, tick.seq, occupancy, &metrics) != 0) {
				goto fail;
			}
		}
	}

	if (send_metric(metric_push, &opts, chipsim_fifo_size(&fifo), &metrics) != 0) {
		goto fail;
	}

	nng_socket_close(metric_push);
	if (opts.sync_mode != CHIPSIM_SYNC_PUBSUB_ONLY) {
		nng_socket_close(done_push);
	}
	if (has_input) {
		nng_socket_close(data_sub);
	}
	nng_socket_close(data_pub);
	nng_socket_close(clock_sub);
	chipsim_fifo_free(&fifo);
	nng_fini();
	return 0;

fail:
	if (nng_socket_id(metric_push) > 0) {
		nng_socket_close(metric_push);
	}
	if (nng_socket_id(done_push) > 0) {
		nng_socket_close(done_push);
	}
	if (nng_socket_id(data_sub) > 0) {
		nng_socket_close(data_sub);
	}
	if (nng_socket_id(data_pub) > 0) {
		nng_socket_close(data_pub);
	}
	if (nng_socket_id(clock_sub) > 0) {
		nng_socket_close(clock_sub);
	}
	chipsim_fifo_free(&fifo);
	nng_fini();
	return 1;
}
