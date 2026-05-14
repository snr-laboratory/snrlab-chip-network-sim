#include <errno.h>
#include <inttypes.h>
#include <nng/nng.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "Vchip_fifo_router.h"
#include "verilated.h"

#include "chipsim/protocol.h"
#include "chipsim/trace.h"

#define CHIPSIM_DEFAULT_CLOCK_URL "tcp://127.0.0.1:23000"
#define CHIPSIM_DEFAULT_METRIC_URL "tcp://127.0.0.1:23002"
#define CHIPSIM_DEFAULT_DATA_PREFIX "tcp://127.0.0.1:%d"
#define CHIPSIM_DEFAULT_DATA_TIMEOUT_MS 5000

#define PACKET_A_BITS 16u
#define PACKET_B_BITS 24u
#define PACKET_C_BITS 24u
#define PACKET_TOTAL_BITS 64u
#define ERRSTR(x) nng_strerror((nng_err) (x))

typedef struct {
	int                 id;
	int                 input_id;
	int                 out_id;
	int                 fifo_depth;
	int                 data_port_base;
	int                 data_timeout_ms;
	uint32_t            seed;
	int                 gen_ppm;
	const char         *clock_url;
	const char         *metric_url;
	const char         *data_prefix;
	const char         *trace_file;
} chip_options_t;

typedef struct {
	uint64_t tx_count;
	uint64_t rx_count;
	uint64_t local_gen_count;
	uint64_t drop_count;
	uint64_t fifo_peak;
	uint64_t last_seq;
} chip_metrics_t;

typedef struct {
	pthread_mutex_t lock;
	pthread_cond_t  cond;
	bool            stop_requested;
	bool            has_published;
	uint64_t        seq;
	bool            has_packet;
	chipsim_packet_t packet;
	nng_socket      data_rep;
	int             chip_id;
} data_server_state_t;

static void
usage(const char *prog)
{
	fprintf(stderr,
	    "Usage: %s -id <chip_id> -input <chip_id|-1> -out <chip_id|-1> [options]\n"
	    "Options:\n"
	    "  -fifo_depth <N>      local FIFO depth (default 32)\n"
	    "  -gen_ppm <N>         local generation rate per tick in ppm [0..1e6] "
	    "(default 100000)\n"
	    "  -seed <N>            RNG seed (default 1)\n"
	    "  -clock_url <URI>     orchestrator control endpoint (REQ/REP)\n"
	    "  -metric_url <URI>    orchestrator metric endpoint\n"
	    "  -data_prefix <URI>   per-chip data endpoint prefix or printf pattern\n"
	    "  -data_port_base <N>  numeric base added to chip id when using %%d pattern\n"
	    "  -data_timeout_ms <N> upstream data pull timeout (default 5000)\n"
	    "  -trace_file <path>   optional binary trace output path\n",
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
	opts->id              = -1;
	opts->input_id        = -1;
	opts->out_id          = -1;
	opts->fifo_depth      = 32;
	opts->data_port_base  = 0;
	opts->data_timeout_ms = CHIPSIM_DEFAULT_DATA_TIMEOUT_MS;
	opts->seed            = 1u;
	opts->gen_ppm         = 100000;
	opts->clock_url       = CHIPSIM_DEFAULT_CLOCK_URL;
	opts->metric_url      = CHIPSIM_DEFAULT_METRIC_URL;
	opts->data_prefix     = CHIPSIM_DEFAULT_DATA_PREFIX;
	opts->trace_file      = NULL;

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
		} else if (strcmp(argv[i], "-fifo_depth") == 0 && i + 1 < argc) {
			if (parse_int(argv[++i], &opts->fifo_depth) != 0 || opts->fifo_depth <= 0 ||
			    opts->fifo_depth > 65535) {
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
		} else if (strcmp(argv[i], "-metric_url") == 0 && i + 1 < argc) {
			opts->metric_url = argv[++i];
		} else if (strcmp(argv[i], "-data_prefix") == 0 && i + 1 < argc) {
			opts->data_prefix = argv[++i];
		} else if (strcmp(argv[i], "-data_port_base") == 0 && i + 1 < argc) {
			if (parse_int(argv[++i], &opts->data_port_base) != 0 || opts->data_port_base < 0 ||
			    opts->data_port_base > 65535) {
				return -1;
			}
		} else if (strcmp(argv[i], "-data_timeout_ms") == 0 && i + 1 < argc) {
			if (parse_int(argv[++i], &opts->data_timeout_ms) != 0 || opts->data_timeout_ms <= 0) {
				return -1;
			}
		} else if (strcmp(argv[i], "-trace_file") == 0 && i + 1 < argc) {
			opts->trace_file = argv[++i];
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
build_data_url(char *dst, size_t dst_len, const char *prefix, int chip_id, int data_port_base)
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

static uint64_t
pack_packet(const chipsim_packet_t *packet)
{
	uint64_t src_mask = (1ULL << PACKET_A_BITS) - 1ULL;
	uint64_t ts_mask  = (1ULL << PACKET_B_BITS) - 1ULL;
	uint64_t pay_mask = (1ULL << PACKET_C_BITS) - 1ULL;
	uint64_t word     = 0;

	(void) PACKET_TOTAL_BITS;
	word |= ((uint64_t) packet->src_id & src_mask) << (PACKET_B_BITS + PACKET_C_BITS);
	word |= ((uint64_t) packet->timestamp & ts_mask) << PACKET_C_BITS;
	word |= ((uint64_t) packet->payload & pay_mask);
	return word;
}

static chipsim_packet_t
unpack_packet(uint64_t word)
{
	uint64_t         src_mask = (1ULL << PACKET_A_BITS) - 1ULL;
	uint64_t         ts_mask  = (1ULL << PACKET_B_BITS) - 1ULL;
	uint64_t         pay_mask = (1ULL << PACKET_C_BITS) - 1ULL;
	chipsim_packet_t packet;

	memset(&packet, 0, sizeof(packet));
	packet.src_id    = (uint32_t) ((word >> (PACKET_B_BITS + PACKET_C_BITS)) & src_mask);
	packet.timestamp = (uint64_t) ((word >> PACKET_C_BITS) & ts_mask);
	packet.payload   = (uint32_t) (word & pay_mask);
	return packet;
}

static int
send_done(nng_socket control_rep, const chip_options_t *opts, uint64_t seq, uint64_t fifo_occupancy,
    const chip_metrics_t *metrics)
{
	chipsim_done_msg_t done;
	int                rv;

	memset(&done, 0, sizeof(done));
	done.type            = CHIPSIM_MSG_DONE;
	done.chip_id         = (uint32_t) opts->id;
	done.seq             = seq;
	done.tx_count        = metrics->tx_count;
	done.rx_count        = metrics->rx_count;
	done.local_gen_count = metrics->local_gen_count;
	done.drop_count      = metrics->drop_count;
	done.fifo_occupancy  = fifo_occupancy;

	rv = nng_send(control_rep, &done, sizeof(done), 0);
	if (rv != 0) {
		fprintf(stderr, "chip_rtl[%d] failed to send DONE: %s\n", opts->id, ERRSTR(rv));
		return -1;
	}
	return 0;
}

static int
send_metric(nng_socket metric_push, const chip_options_t *opts, uint64_t fifo_occupancy,
    const chip_metrics_t *metrics)
{
	chipsim_metric_msg_t m;
	int                  rv;

	memset(&m, 0, sizeof(m));
	m.type            = CHIPSIM_MSG_METRIC;
	m.chip_id         = (uint32_t) opts->id;
	m.seq             = metrics->last_seq;
	m.tx_count        = metrics->tx_count;
	m.rx_count        = metrics->rx_count;
	m.local_gen_count = metrics->local_gen_count;
	m.drop_count      = metrics->drop_count;
	m.fifo_occupancy  = fifo_occupancy;
	m.fifo_peak       = metrics->fifo_peak;

	rv = nng_send(metric_push, &m, sizeof(m), 0);
	if (rv != 0) {
		fprintf(stderr, "chip_rtl[%d] failed to send METRIC: %s\n", opts->id, ERRSTR(rv));
		return -1;
	}
	return 0;
}

static int
data_server_init(data_server_state_t *state, nng_socket data_rep, int chip_id)
{
	memset(state, 0, sizeof(*state));
	state->data_rep = data_rep;
	state->chip_id  = chip_id;
	if (pthread_mutex_init(&state->lock, NULL) != 0) {
		return -1;
	}
	if (pthread_cond_init(&state->cond, NULL) != 0) {
		pthread_mutex_destroy(&state->lock);
		return -1;
	}
	return 0;
}

static void
data_server_destroy(data_server_state_t *state)
{
	pthread_cond_destroy(&state->cond);
	pthread_mutex_destroy(&state->lock);
}

static void
data_server_publish(data_server_state_t *state, uint64_t seq, bool has_packet,
    const chipsim_packet_t *packet)
{
	pthread_mutex_lock(&state->lock);
	state->has_published = true;
	state->seq           = seq;
	state->has_packet    = has_packet;
	if (has_packet && packet != NULL) {
		state->packet = *packet;
	}
	pthread_cond_broadcast(&state->cond);
	pthread_mutex_unlock(&state->lock);
}

static void
data_server_request_stop(data_server_state_t *state)
{
	pthread_mutex_lock(&state->lock);
	state->stop_requested = true;
	pthread_cond_broadcast(&state->cond);
	pthread_mutex_unlock(&state->lock);
}

static void *
data_server_thread_main(void *arg)
{
	data_server_state_t *state = (data_server_state_t *) arg;

	for (;;) {
		chipsim_data_pull_msg_t  req;
		chipsim_data_reply_msg_t rep;
		size_t                  req_sz = sizeof(req);
		int                     rv;

		rv = nng_recv(state->data_rep, &req, &req_sz, 0);
		if (rv != 0) {
			break;
		}
		if (req_sz != sizeof(req) || req.type != CHIPSIM_MSG_DATA_PULL) {
			continue;
		}

		memset(&rep, 0, sizeof(rep));
		rep.type         = CHIPSIM_MSG_DATA_REPLY;
		rep.responder_id = (uint32_t) state->chip_id;
		rep.seq          = req.seq;

		pthread_mutex_lock(&state->lock);
		while (!state->stop_requested && (!state->has_published || state->seq < req.seq)) {
			pthread_cond_wait(&state->cond, &state->lock);
		}
		if (!state->stop_requested && state->has_published && state->seq == req.seq &&
		    state->has_packet) {
			rep.has_packet = 1u;
			rep.packet     = state->packet;
		}
		pthread_mutex_unlock(&state->lock);

		rv = nng_send(state->data_rep, &rep, sizeof(rep), 0);
		if (rv != 0) {
			break;
		}
	}
	return NULL;
}

static int
pull_from_upstream(nng_socket data_req, const chip_options_t *opts, uint64_t seq,
    chipsim_packet_t *packet, bool *have_packet)
{
	chipsim_data_pull_msg_t  req;
	chipsim_data_reply_msg_t rep;
	size_t                  rep_sz;
	int                     rv;

	memset(&req, 0, sizeof(req));
	req.type         = CHIPSIM_MSG_DATA_PULL;
	req.requester_id = (uint32_t) opts->id;
	req.seq          = seq;

	rv = nng_send(data_req, &req, sizeof(req), 0);
	if (rv != 0) {
		fprintf(stderr, "chip_rtl[%d] send(data_req) failed: %s\n", opts->id, ERRSTR(rv));
		return -1;
	}

	rep_sz = sizeof(rep);
	rv     = nng_recv(data_req, &rep, &rep_sz, 0);
	if (rv != 0) {
		fprintf(stderr, "chip_rtl[%d] recv(data_reply) failed: %s\n", opts->id, ERRSTR(rv));
		return -1;
	}
	if (rep_sz != sizeof(rep) || rep.type != CHIPSIM_MSG_DATA_REPLY) {
		fprintf(stderr, "chip_rtl[%d] malformed data reply\n", opts->id);
		return -1;
	}
	if (rep.seq != seq) {
		fprintf(stderr, "chip_rtl[%d] data reply seq=%" PRIu64 " expected=%" PRIu64 "\n", opts->id,
		    rep.seq, seq);
		return -1;
	}
	if (rep.responder_id != (uint32_t) opts->input_id) {
		fprintf(stderr, "chip_rtl[%d] data reply responder_id=%u expected=%d\n", opts->id,
		    rep.responder_id, opts->input_id);
		return -1;
	}

	if (rep.has_packet) {
		*packet      = rep.packet;
		*have_packet = true;
	} else {
		*have_packet = false;
	}
	return 0;
}

static void
tick_model(Vchip_fifo_router *model)
{
	model->clk = 0;
	model->eval();
	model->clk = 1;
	model->eval();
	model->clk = 0;
	model->eval();
}

int
main(int argc, char **argv)
{
	chip_options_t      opts;
	chip_metrics_t      metrics;
	nng_socket          control_rep = NNG_SOCKET_INITIALIZER;
	nng_socket          data_req    = NNG_SOCKET_INITIALIZER;
	nng_socket          data_rep    = NNG_SOCKET_INITIALIZER;
	nng_socket          metric_push = NNG_SOCKET_INITIALIZER;
	char                my_data_url[256];
	char                input_data_url[256];
	bool                has_input;
	bool                has_output;
	uint32_t            rng_state;
	nng_err             init_err;
	int                 rv;
	int                 exit_code = 1;
	data_server_state_t data_state;
	bool                data_state_inited  = false;
	bool                data_thread_started = false;
	pthread_t           data_thread;
	chipsim_trace_writer_t trace;

	Vchip_fifo_router *model = NULL;

	if (parse_args(argc, argv, &opts) != 0) {
		usage(argv[0]);
		return 2;
	}
	has_input  = opts.input_id >= 0;
	has_output = opts.out_id >= 0;
	memset(&metrics, 0, sizeof(metrics));
	memset(&trace, 0, sizeof(trace));

	init_err = nng_init(NULL);
	if (init_err != 0) {
		fprintf(stderr, "chip_rtl nng_init failed: %s\n", nng_strerror(init_err));
		return 1;
	}

	model = new Vchip_fifo_router();
	model->rst_n          = 0;
	model->cfg_fifo_depth = (uint16_t) opts.fifo_depth;
	model->local_valid    = 0;
	model->local_data     = 0;
	model->neigh_valid    = 0;
	model->neigh_data     = 0;
	model->out_ready      = 1;
	tick_model(model);
	model->rst_n = 1;
	tick_model(model);

	if (chipsim_trace_open(&trace, opts.trace_file, (uint32_t) opts.id) != 0) {
		goto cleanup;
	}

	if (build_data_url(
	        my_data_url, sizeof(my_data_url), opts.data_prefix, opts.id, opts.data_port_base) != 0) {
		fprintf(stderr, "chip_rtl[%d] invalid data prefix\n", opts.id);
		goto cleanup;
	}
	if (has_input && build_data_url(input_data_url, sizeof(input_data_url), opts.data_prefix,
	                     opts.input_id, opts.data_port_base) != 0) {
		fprintf(stderr, "chip_rtl[%d] invalid data prefix for input\n", opts.id);
		goto cleanup;
	}

	rv = nng_rep0_open(&control_rep);
	if (rv != 0) {
		fprintf(stderr, "chip_rtl[%d] nng_rep0_open(control) failed: %s\n", opts.id, ERRSTR(rv));
		goto cleanup;
	}
	rv = nng_listen(control_rep, opts.clock_url, NULL, 0);
	if (rv != 0) {
		fprintf(stderr, "chip_rtl[%d] listen(control) failed at %s: %s\n", opts.id, opts.clock_url,
		    ERRSTR(rv));
		goto cleanup;
	}

	if (has_output) {
		rv = nng_rep0_open(&data_rep);
		if (rv != 0) {
			fprintf(stderr, "chip_rtl[%d] nng_rep0_open(data_rep) failed: %s\n", opts.id,
			    ERRSTR(rv));
			goto cleanup;
		}
		rv = nng_listen(data_rep, my_data_url, NULL, 0);
		if (rv != 0) {
			fprintf(stderr, "chip_rtl[%d] listen(data_rep) failed at %s: %s\n", opts.id,
			    my_data_url, ERRSTR(rv));
			goto cleanup;
		}
		if (data_server_init(&data_state, data_rep, opts.id) != 0) {
			fprintf(stderr, "chip_rtl[%d] data server init failed\n", opts.id);
			goto cleanup;
		}
		data_state_inited = true;
		if (pthread_create(&data_thread, NULL, data_server_thread_main, &data_state) != 0) {
			fprintf(stderr, "chip_rtl[%d] data server thread create failed\n", opts.id);
			goto cleanup;
		}
		data_thread_started = true;
	}

	if (has_input) {
		rv = nng_req0_open(&data_req);
		if (rv != 0) {
			fprintf(stderr, "chip_rtl[%d] nng_req0_open(data_req) failed: %s\n", opts.id,
			    ERRSTR(rv));
			goto cleanup;
		}
		rv = nng_socket_set_ms(data_req, NNG_OPT_SENDTIMEO, opts.data_timeout_ms);
		if (rv != 0) {
			fprintf(stderr, "chip_rtl[%d] set send timeout data_req failed: %s\n", opts.id,
			    ERRSTR(rv));
			goto cleanup;
		}
		rv = nng_socket_set_ms(data_req, NNG_OPT_RECVTIMEO, opts.data_timeout_ms);
		if (rv != 0) {
			fprintf(stderr, "chip_rtl[%d] set recv timeout data_req failed: %s\n", opts.id,
			    ERRSTR(rv));
			goto cleanup;
		}
		rv = nng_socket_set_ms(data_req, NNG_OPT_REQ_RESENDTIME, NNG_DURATION_INFINITE);
		if (rv != 0) {
			fprintf(stderr, "chip_rtl[%d] set req resend data_req failed: %s\n", opts.id,
			    ERRSTR(rv));
			goto cleanup;
		}
		rv = nng_dial(data_req, input_data_url, NULL, NNG_FLAG_NONBLOCK);
		if (rv != 0) {
			fprintf(stderr, "chip_rtl[%d] dial(data_req) failed at %s: %s\n", opts.id,
			    input_data_url, ERRSTR(rv));
			goto cleanup;
		}
	}

	rv = nng_push0_open(&metric_push);
	if (rv != 0) {
		fprintf(stderr, "chip_rtl[%d] nng_push0_open(metric) failed: %s\n", opts.id, ERRSTR(rv));
		goto cleanup;
	}
	rv = nng_dial(metric_push, opts.metric_url, NULL, 0);
	if (rv != 0) {
		fprintf(stderr, "chip_rtl[%d] dial(metric) failed: %s\n", opts.id, ERRSTR(rv));
		goto cleanup;
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
		bool               have_out      = false;
		uint64_t           local_word    = 0;
		uint64_t           neigh_word    = 0;
		bool               emit_valid;
		uint64_t           emit_word;
		uint32_t           draw;

		rv = nng_recv(control_rep, &tick, &tick_sz, 0);
		if (rv != 0) {
			fprintf(stderr, "chip_rtl[%d] recv(control) failed: %s\n", opts.id, ERRSTR(rv));
			goto cleanup;
		}
		if (tick_sz != sizeof(tick)) {
			fprintf(stderr, "chip_rtl[%d] recv(control) malformed size=%zu expected=%zu\n", opts.id,
			    tick_sz, sizeof(tick));
			goto cleanup;
		}
		metrics.last_seq = tick.seq;
		if (tick.type == CHIPSIM_MSG_STOP) {
			if (has_output) {
				data_server_publish(&data_state, tick.seq, false, NULL);
			}
			if (send_done(control_rep, &opts, tick.seq, (uint64_t) model->occupancy, &metrics) != 0) {
				goto cleanup;
			}
			break;
		}
		if (tick.type != CHIPSIM_MSG_TICK) {
			fprintf(stderr, "chip_rtl[%d] recv(control) unknown type=%u\n", opts.id,
			    (unsigned) tick.type);
			goto cleanup;
		}

		emit_valid = (model->out_valid != 0);
		emit_word  = model->out_data;
		if (emit_valid) {
			out_packet = unpack_packet(emit_word);
			have_out   = true;
			if (chipsim_trace_emit_fields(&trace, tick.seq, CHIPSIM_TRACE_EVT_DEQ_OUT,
			        (uint32_t) model->occupancy, emit_word) != 0) {
				goto cleanup;
			}
		}
		if (has_output) {
			data_server_publish(&data_state, tick.seq, have_out, have_out ? &out_packet : NULL);
			if (have_out) {
				metrics.tx_count++;
			}
		}

		if (has_input) {
			if (pull_from_upstream(data_req, &opts, tick.seq, &neighbor_packet, &have_neighbor) != 0) {
				goto cleanup;
			}
			if (have_neighbor) {
				neigh_word = pack_packet(&neighbor_packet);
				metrics.rx_count++;
			}
		}

		draw = xorshift32(&rng_state) % 1000000u;
		if (draw < (uint32_t) opts.gen_ppm) {
			memset(&local_packet, 0, sizeof(local_packet));
			local_packet.src_id    = (uint32_t) opts.id;
			local_packet.timestamp = tick.seq;
			local_packet.payload   = xorshift32(&rng_state) & 0x00FFFFFFu;
			local_packet.seq_local = metrics.local_gen_count;
			local_word             = pack_packet(&local_packet);
			have_local             = true;
			metrics.local_gen_count++;
			if (chipsim_trace_emit_fields(&trace, tick.seq, CHIPSIM_TRACE_EVT_GEN_LOCAL,
			        (uint32_t) model->occupancy, local_word) != 0) {
				goto cleanup;
			}
		}

		model->cfg_fifo_depth = (uint16_t) opts.fifo_depth;
		model->local_valid    = have_local ? 1 : 0;
		model->local_data     = local_word;
		model->neigh_valid    = have_neighbor ? 1 : 0;
		model->neigh_data     = neigh_word;
		model->out_ready      = 1;
		tick_model(model);

		if (model->drop_local) {
			metrics.drop_count++;
		}
		if (model->drop_neigh) {
			metrics.drop_count++;
		}
		if ((uint64_t) model->occupancy > metrics.fifo_peak) {
			metrics.fifo_peak = (uint64_t) model->occupancy;
		}
		if (have_local) {
			if (chipsim_trace_emit_fields(&trace, tick.seq,
			        model->drop_local ? CHIPSIM_TRACE_EVT_ENQ_LOCAL_DROP_FULL :
			                    CHIPSIM_TRACE_EVT_ENQ_LOCAL_OK,
			        (uint32_t) model->occupancy, local_word) != 0) {
				goto cleanup;
			}
		}
		if (have_neighbor) {
			if (chipsim_trace_emit_fields(&trace, tick.seq,
			        model->drop_neigh ? CHIPSIM_TRACE_EVT_ENQ_NEIGH_DROP_FULL :
			                    CHIPSIM_TRACE_EVT_ENQ_NEIGH_OK,
			        (uint32_t) model->occupancy, neigh_word) != 0) {
				goto cleanup;
			}
		}

		if (send_done(control_rep, &opts, tick.seq, (uint64_t) model->occupancy, &metrics) != 0) {
			goto cleanup;
		}
	}

	if (send_metric(metric_push, &opts, (uint64_t) model->occupancy, &metrics) != 0) {
		goto cleanup;
	}

	exit_code = 0;

cleanup:
	if (data_thread_started) {
		data_server_request_stop(&data_state);
	}
	if (nng_socket_id(data_req) > 0) {
		nng_socket_close(data_req);
	}
	if (nng_socket_id(data_rep) > 0) {
		nng_socket_close(data_rep);
	}
	if (data_thread_started) {
		pthread_join(data_thread, NULL);
	}
	if (data_state_inited) {
		data_server_destroy(&data_state);
	}
	if (nng_socket_id(metric_push) > 0) {
		nng_socket_close(metric_push);
	}
	if (nng_socket_id(control_rep) > 0) {
		nng_socket_close(control_rep);
	}
	chipsim_trace_close(&trace);
	if (model != NULL) {
		delete model;
	}
	nng_fini();
	return exit_code;
}
