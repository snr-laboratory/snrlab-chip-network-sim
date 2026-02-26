#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <inttypes.h>
#include <nng/nng.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#include "chipsim/protocol.h"

typedef enum {
	ROUTE_EAST = 0,
	ROUTE_WEST = 1,
	ROUTE_SOUTH = 2,
	ROUTE_NORTH = 3
} route_mode_t;

typedef struct {
	int                 rows;
	int                 cols;
	uint64_t            ticks;
	int                 fifo_depth;
	int                 gen_ppm;
	uint32_t            seed;
	int                 startup_ms;
	int                 ack_timeout_ms;
	int                 ack_window;
	chipsim_sync_mode_t sync_mode;
	route_mode_t        route_mode;
	const char         *chip_bin;
	const char         *base_uri;
} orchestrator_options_t;

static void
usage(const char *prog)
{
	fprintf(stderr,
	    "Usage: %s -rows <R> -cols <C> -ticks <N> "
	    "[-sync barrier_ack|pubsub_only|windowed_ack] [options]\n"
	    "Options:\n"
	    "  -route <east|west|south|north>  static output direction (default east)\n"
	    "  -fifo_depth <N>                 FIFO depth per chip (default 32)\n"
	    "  -gen_ppm <N>                    local generation rate in ppm (default 100000)\n"
	    "  -seed <N>                       base seed (default 1)\n"
	    "  -ack_window <N>                 window for windowed_ack (default 4)\n"
	    "  -startup_ms <N>                 wait before first tick (default 350)\n"
	    "  -ack_timeout_ms <N>             timeout waiting for ACK/METRIC (default 5000)\n"
	    "  -chip_bin <path>                chip executable (default ./chip)\n"
	    "  -base_uri <tcp://127.0.0.1:PORT> endpoint base port (default auto)\n",
	    prog);
}

static int
parse_int(const char *value, int *out)
{
	long v;
	char *end;

	errno = 0;
	v     = strtol(value, &end, 10);
	if (errno != 0 || end == value || *end != '\0' || v < INT32_MIN || v > INT32_MAX) {
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
parse_u64(const char *value, uint64_t *out)
{
	unsigned long long v;
	char              *end;

	errno = 0;
	v     = strtoull(value, &end, 10);
	if (errno != 0 || end == value || *end != '\0') {
		return -1;
	}
	*out = (uint64_t) v;
	return 0;
}

static int
parse_route(const char *value, route_mode_t *mode)
{
	if (strcmp(value, "east") == 0) {
		*mode = ROUTE_EAST;
		return 0;
	}
	if (strcmp(value, "west") == 0) {
		*mode = ROUTE_WEST;
		return 0;
	}
	if (strcmp(value, "south") == 0) {
		*mode = ROUTE_SOUTH;
		return 0;
	}
	if (strcmp(value, "north") == 0) {
		*mode = ROUTE_NORTH;
		return 0;
	}
	return -1;
}

static int
parse_args(int argc, char **argv, orchestrator_options_t *opts)
{
	int i;

	memset(opts, 0, sizeof(*opts));
	opts->rows          = 0;
	opts->cols          = 0;
	opts->ticks         = 0;
	opts->fifo_depth    = 32;
	opts->gen_ppm       = 100000;
	opts->seed          = 1u;
	opts->startup_ms    = 350;
	opts->ack_timeout_ms = 5000;
	opts->ack_window    = 4;
	opts->sync_mode     = CHIPSIM_SYNC_BARRIER_ACK;
	opts->route_mode    = ROUTE_EAST;
	opts->chip_bin      = "./chip";
	opts->base_uri      = NULL;

	for (i = 1; i < argc; i++) {
		if (strcmp(argv[i], "-rows") == 0 && i + 1 < argc) {
			if (parse_int(argv[++i], &opts->rows) != 0 || opts->rows <= 0) {
				return -1;
			}
		} else if (strcmp(argv[i], "-cols") == 0 && i + 1 < argc) {
			if (parse_int(argv[++i], &opts->cols) != 0 || opts->cols <= 0) {
				return -1;
			}
		} else if (strcmp(argv[i], "-ticks") == 0 && i + 1 < argc) {
			if (parse_u64(argv[++i], &opts->ticks) != 0 || opts->ticks == 0) {
				return -1;
			}
		} else if (strcmp(argv[i], "-sync") == 0 && i + 1 < argc) {
			if (chipsim_parse_sync_mode(argv[++i], &opts->sync_mode) != 0) {
				return -1;
			}
		} else if (strcmp(argv[i], "-route") == 0 && i + 1 < argc) {
			if (parse_route(argv[++i], &opts->route_mode) != 0) {
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
		} else if (strcmp(argv[i], "-startup_ms") == 0 && i + 1 < argc) {
			if (parse_int(argv[++i], &opts->startup_ms) != 0 || opts->startup_ms < 0) {
				return -1;
			}
		} else if (strcmp(argv[i], "-ack_timeout_ms") == 0 && i + 1 < argc) {
			if (parse_int(argv[++i], &opts->ack_timeout_ms) != 0 || opts->ack_timeout_ms <= 0) {
				return -1;
			}
		} else if (strcmp(argv[i], "-ack_window") == 0 && i + 1 < argc) {
			if (parse_int(argv[++i], &opts->ack_window) != 0 || opts->ack_window <= 0) {
				return -1;
			}
		} else if (strcmp(argv[i], "-chip_bin") == 0 && i + 1 < argc) {
			opts->chip_bin = argv[++i];
		} else if (strcmp(argv[i], "-base_uri") == 0 && i + 1 < argc) {
			opts->base_uri = argv[++i];
		} else {
			return -1;
		}
	}

	if (opts->rows <= 0 || opts->cols <= 0 || opts->ticks == 0) {
		return -1;
	}
	return 0;
}

static int
build_endpoints(const orchestrator_options_t *opts, char *clock_url, size_t clock_len,
    char *done_url, size_t done_len, char *metric_url, size_t metric_len, char *data_prefix,
    size_t data_prefix_len, int *data_port_base)
{
	int        base_port = 0;
	int        n;
	const char tcp_prefix[] = "tcp://127.0.0.1:";

	if (opts->base_uri != NULL) {
		const char *start = NULL;
		if (strncmp(opts->base_uri, tcp_prefix, strlen(tcp_prefix)) != 0) {
			fprintf(stderr, "base_uri must look like tcp://127.0.0.1:<port>\n");
			return -1;
		}
		start = opts->base_uri + (int) strlen(tcp_prefix);
		if (parse_int(start, &base_port) != 0) {
			fprintf(stderr, "invalid base_uri port in %s\n", opts->base_uri);
			return -1;
		}
	} else {
		base_port = 24000 + ((int) (getpid() % 10000));
	}
	if (base_port <= 1024 || base_port >= 65000) {
		return -1;
	}

	n = snprintf(clock_url, clock_len, "tcp://127.0.0.1:%d", base_port);
	if (n < 0 || (size_t) n >= clock_len) {
		return -1;
	}
	n = snprintf(done_url, done_len, "tcp://127.0.0.1:%d", base_port + 1);
	if (n < 0 || (size_t) n >= done_len) {
		return -1;
	}
	n = snprintf(metric_url, metric_len, "tcp://127.0.0.1:%d", base_port + 2);
	if (n < 0 || (size_t) n >= metric_len) {
		return -1;
	}
	n = snprintf(data_prefix, data_prefix_len, "tcp://127.0.0.1:%%d");
	if (n < 0 || (size_t) n >= data_prefix_len) {
		return -1;
	}
	*data_port_base = base_port + 100;
	if (*data_port_base + (opts->rows * opts->cols) >= 65535) {
		fprintf(stderr, "port range exhausted for requested topology\n");
		return -1;
	}
	return 0;
}

static int
compute_out_id(route_mode_t route, int rows, int cols, int id)
{
	int r = id / cols;
	int c = id % cols;

	switch (route) {
	case ROUTE_EAST:
		return (c + 1 < cols) ? (id + 1) : -1;
	case ROUTE_WEST:
		return (c > 0) ? (id - 1) : -1;
	case ROUTE_SOUTH:
		return (r + 1 < rows) ? (id + cols) : -1;
	case ROUTE_NORTH:
		return (r > 0) ? (id - cols) : -1;
	default:
		return -1;
	}
}

static int
build_routes(const orchestrator_options_t *opts, int *input_ids, int *out_ids)
{
	int rows   = opts->rows;
	int cols   = opts->cols;
	int chips  = rows * cols;
	int chip_i = 0;

	for (chip_i = 0; chip_i < chips; chip_i++) {
		input_ids[chip_i] = -1;
		out_ids[chip_i]   = compute_out_id(opts->route_mode, rows, cols, chip_i);
	}

	for (chip_i = 0; chip_i < chips; chip_i++) {
		int out = out_ids[chip_i];
		if (out < 0) {
			continue;
		}
		if (out >= chips) {
			fprintf(stderr, "invalid route: chip %d out=%d outside topology\n", chip_i, out);
			return -1;
		}
		if (input_ids[out] != -1) {
			fprintf(stderr,
			    "invalid 1-in route: chip %d and chip %d both feed chip %d\n", input_ids[out],
			    chip_i, out);
			return -1;
		}
		input_ids[out] = chip_i;
	}

	return 0;
}

static int
launch_chip(const orchestrator_options_t *opts, const char *clock_url, const char *done_url,
    const char *metric_url, const char *data_prefix, int data_port_base, int chip_id, int input_id,
    int out_id, pid_t *child_pid)
{
	pid_t pid;
	char  id_s[32], input_s[32], out_s[32], ack_s[32], fifo_s[32], gen_s[32], seed_s[32],
	    data_port_base_s[32];
	char *argv_exec[32];
	int   idx = 0;

	snprintf(id_s, sizeof(id_s), "%d", chip_id);
	snprintf(input_s, sizeof(input_s), "%d", input_id);
	snprintf(out_s, sizeof(out_s), "%d", out_id);
	snprintf(ack_s, sizeof(ack_s), "%d", opts->ack_window);
	snprintf(fifo_s, sizeof(fifo_s), "%d", opts->fifo_depth);
	snprintf(gen_s, sizeof(gen_s), "%d", opts->gen_ppm);
	snprintf(seed_s, sizeof(seed_s), "%u", (unsigned) (opts->seed + (uint32_t) chip_id));
	snprintf(data_port_base_s, sizeof(data_port_base_s), "%d", data_port_base);

	argv_exec[idx++] = (char *) opts->chip_bin;
	argv_exec[idx++] = "-id";
	argv_exec[idx++] = id_s;
	argv_exec[idx++] = "-input";
	argv_exec[idx++] = input_s;
	argv_exec[idx++] = "-out";
	argv_exec[idx++] = out_s;
	argv_exec[idx++] = "-sync";
	argv_exec[idx++] = (char *) chipsim_sync_mode_name(opts->sync_mode);
	argv_exec[idx++] = "-ack_window";
	argv_exec[idx++] = ack_s;
	argv_exec[idx++] = "-fifo_depth";
	argv_exec[idx++] = fifo_s;
	argv_exec[idx++] = "-gen_ppm";
	argv_exec[idx++] = gen_s;
	argv_exec[idx++] = "-seed";
	argv_exec[idx++] = seed_s;
	argv_exec[idx++] = "-clock_url";
	argv_exec[idx++] = (char *) clock_url;
	argv_exec[idx++] = "-done_url";
	argv_exec[idx++] = (char *) done_url;
	argv_exec[idx++] = "-metric_url";
	argv_exec[idx++] = (char *) metric_url;
	argv_exec[idx++] = "-data_prefix";
	argv_exec[idx++] = (char *) data_prefix;
	argv_exec[idx++] = "-data_port_base";
	argv_exec[idx++] = data_port_base_s;
	argv_exec[idx++] = NULL;

	pid = fork();
	if (pid < 0) {
		perror("fork");
		return -1;
	}
	if (pid == 0) {
		execvp(opts->chip_bin, argv_exec);
		perror("execvp(chip)");
		_exit(127);
	}

	*child_pid = pid;
	return 0;
}

static void
terminate_children(pid_t *pids, int count)
{
	int i;

	for (i = 0; i < count; i++) {
		if (pids[i] > 0) {
			kill(pids[i], SIGTERM);
		}
	}
}

static int
wait_done_for_seq(nng_socket done_pull, int chip_count, uint64_t expected_seq, chipsim_done_msg_t *latest)
{
	bool *seen;
	int   received = 0;

	seen = calloc((size_t) chip_count, sizeof(bool));
	if (seen == NULL) {
		return -1;
	}

	while (received < chip_count) {
		chipsim_done_msg_t msg;
		size_t             msg_sz = sizeof(msg);
		int                rv     = nng_recv(done_pull, &msg, &msg_sz, 0);
		if (rv != 0) {
			fprintf(stderr, "orchestrator recv(DONE) failed: %s\n", nng_strerror(rv));
			free(seen);
			return -1;
		}
		if (msg_sz != sizeof(msg) || msg.type != CHIPSIM_MSG_DONE) {
			continue;
		}
		if (msg.seq < expected_seq) {
			continue;
		}
		if (msg.seq > expected_seq) {
			fprintf(stderr, "orchestrator received DONE future seq=%" PRIu64 " expected=%" PRIu64
			                "\n",
			    msg.seq, expected_seq);
			free(seen);
			return -1;
		}
		if (msg.chip_id >= (uint32_t) chip_count) {
			fprintf(stderr, "orchestrator received DONE with invalid chip_id=%u\n", msg.chip_id);
			free(seen);
			return -1;
		}
		if (!seen[msg.chip_id]) {
			seen[msg.chip_id] = true;
			received++;
		}
		latest[msg.chip_id] = msg;
	}

	free(seen);
	return 0;
}

static int
collect_metrics(nng_socket metric_pull, int chip_count, chipsim_metric_msg_t *metrics)
{
	bool *seen;
	int   received = 0;

	seen = calloc((size_t) chip_count, sizeof(bool));
	if (seen == NULL) {
		return -1;
	}
	while (received < chip_count) {
		chipsim_metric_msg_t msg;
		size_t               msg_sz = sizeof(msg);
		int                  rv     = nng_recv(metric_pull, &msg, &msg_sz, 0);
		if (rv != 0) {
			fprintf(stderr, "orchestrator recv(METRIC) failed: %s\n", nng_strerror(rv));
			free(seen);
			return -1;
		}
		if (msg_sz != sizeof(msg) || msg.type != CHIPSIM_MSG_METRIC) {
			continue;
		}
		if (msg.chip_id >= (uint32_t) chip_count) {
			fprintf(stderr, "orchestrator received METRIC with invalid chip_id=%u\n", msg.chip_id);
			free(seen);
			return -1;
		}
		if (!seen[msg.chip_id]) {
			seen[msg.chip_id] = true;
			received++;
		}
		metrics[msg.chip_id] = msg;
	}
	free(seen);
	return 0;
}

int
main(int argc, char **argv)
{
	orchestrator_options_t opts;
	int                    chip_count;
	int                   *input_ids   = NULL;
	int                   *out_ids     = NULL;
	pid_t                 *child_pids  = NULL;
	chipsim_done_msg_t    *done_latest = NULL;
	chipsim_metric_msg_t  *metric_all  = NULL;
	nng_socket             clock_pub   = NNG_SOCKET_INITIALIZER;
	nng_socket             done_pull   = NNG_SOCKET_INITIALIZER;
	nng_socket             metric_pull = NNG_SOCKET_INITIALIZER;
	char                   clock_url[256];
	char                   done_url[256];
	char                   metric_url[256];
	char                   data_prefix[256];
	int                    data_port_base = 0;
	int                    rv;
	int                    i;
	uint64_t               seq;
	nng_err                init_err;

	init_err = nng_init(NULL);
	if (init_err != 0) {
		fprintf(stderr, "orchestrator nng_init failed: %s\n", nng_strerror((int) init_err));
		return 1;
	}

	if (parse_args(argc, argv, &opts) != 0) {
		usage(argv[0]);
		return 2;
	}
	chip_count = opts.rows * opts.cols;

	if (build_endpoints(&opts, clock_url, sizeof(clock_url), done_url, sizeof(done_url), metric_url,
	        sizeof(metric_url), data_prefix, sizeof(data_prefix), &data_port_base) != 0) {
		fprintf(stderr, "failed to build endpoints\n");
		return 1;
	}
	printf("orchestrator: rows=%d cols=%d chips=%d ticks=%" PRIu64 " sync=%s route=%d\n", opts.rows,
	    opts.cols, chip_count, opts.ticks, chipsim_sync_mode_name(opts.sync_mode),
	    (int) opts.route_mode);
	printf("orchestrator: clock=%s\n", clock_url);

	input_ids   = calloc((size_t) chip_count, sizeof(int));
	out_ids     = calloc((size_t) chip_count, sizeof(int));
	child_pids  = calloc((size_t) chip_count, sizeof(pid_t));
	done_latest = calloc((size_t) chip_count, sizeof(chipsim_done_msg_t));
	metric_all  = calloc((size_t) chip_count, sizeof(chipsim_metric_msg_t));
	if (input_ids == NULL || out_ids == NULL || child_pids == NULL || done_latest == NULL ||
	    metric_all == NULL) {
		fprintf(stderr, "allocation failure\n");
		goto fail;
	}

	if (build_routes(&opts, input_ids, out_ids) != 0) {
		goto fail;
	}

	rv = nng_pub0_open(&clock_pub);
	if (rv != 0) {
		fprintf(stderr, "nng_pub0_open(clock_pub) failed: %s\n", nng_strerror(rv));
		goto fail;
	}
	rv = nng_listen(clock_pub, clock_url, NULL, 0);
	if (rv != 0) {
		fprintf(stderr, "listen(clock_pub) failed: %s\n", nng_strerror(rv));
		goto fail;
	}

	rv = nng_pull0_open(&done_pull);
	if (rv != 0) {
		fprintf(stderr, "nng_pull0_open(done_pull) failed: %s\n", nng_strerror(rv));
		goto fail;
	}
	rv = nng_socket_set_ms(done_pull, NNG_OPT_RECVTIMEO, opts.ack_timeout_ms);
	if (rv != 0) {
		fprintf(stderr, "set timeout done_pull failed: %s\n", nng_strerror(rv));
		goto fail;
	}
	rv = nng_listen(done_pull, done_url, NULL, 0);
	if (rv != 0) {
		fprintf(stderr, "listen(done_pull) failed: %s\n", nng_strerror(rv));
		goto fail;
	}

	rv = nng_pull0_open(&metric_pull);
	if (rv != 0) {
		fprintf(stderr, "nng_pull0_open(metric_pull) failed: %s\n", nng_strerror(rv));
		goto fail;
	}
	rv = nng_socket_set_ms(metric_pull, NNG_OPT_RECVTIMEO, opts.ack_timeout_ms);
	if (rv != 0) {
		fprintf(stderr, "set timeout metric_pull failed: %s\n", nng_strerror(rv));
		goto fail;
	}
	rv = nng_listen(metric_pull, metric_url, NULL, 0);
	if (rv != 0) {
		fprintf(stderr, "listen(metric_pull) failed: %s\n", nng_strerror(rv));
		goto fail;
	}

	for (i = 0; i < chip_count; i++) {
		if (launch_chip(&opts, clock_url, done_url, metric_url, data_prefix, data_port_base, i,
		        input_ids[i], out_ids[i], &child_pids[i]) != 0) {
			fprintf(stderr, "failed to launch chip %d\n", i);
			goto fail;
		}
	}

	nng_msleep((nng_duration) opts.startup_ms);
	for (seq = 0; seq < opts.ticks; seq++) {
		chipsim_tick_msg_t tick;
		bool               wait_for_done;

		memset(&tick, 0, sizeof(tick));
		tick.type      = CHIPSIM_MSG_TICK;
		tick.sync_mode = (uint8_t) opts.sync_mode;
		tick.seq       = seq;

		rv = nng_send(clock_pub, &tick, sizeof(tick), 0);
		if (rv != 0) {
			fprintf(stderr, "send(TICK) failed for seq=%" PRIu64 ": %s\n", seq, nng_strerror(rv));
			goto fail;
		}

		wait_for_done = false;
		if (opts.sync_mode == CHIPSIM_SYNC_BARRIER_ACK) {
			wait_for_done = true;
		} else if (opts.sync_mode == CHIPSIM_SYNC_WINDOWED_ACK) {
			wait_for_done = ((seq + 1u) % (uint64_t) opts.ack_window) == 0u;
		}
		if (wait_for_done) {
			if (wait_done_for_seq(done_pull, chip_count, seq, done_latest) != 0) {
				goto fail;
			}
		}
	}

	{
		chipsim_tick_msg_t stop_msg;
		memset(&stop_msg, 0, sizeof(stop_msg));
		stop_msg.type      = CHIPSIM_MSG_STOP;
		stop_msg.sync_mode = (uint8_t) opts.sync_mode;
		stop_msg.seq       = opts.ticks;
		rv                 = nng_send(clock_pub, &stop_msg, sizeof(stop_msg), 0);
		if (rv != 0) {
			fprintf(stderr, "send(STOP) failed: %s\n", nng_strerror(rv));
			goto fail;
		}
	}

	if (collect_metrics(metric_pull, chip_count, metric_all) != 0) {
		goto fail;
	}

	{
		uint64_t total_tx = 0;
		uint64_t total_rx = 0;
		uint64_t total_local = 0;
		uint64_t total_drop = 0;
		uint64_t max_peak = 0;

		for (i = 0; i < chip_count; i++) {
			total_tx += metric_all[i].tx_count;
			total_rx += metric_all[i].rx_count;
			total_local += metric_all[i].local_gen_count;
			total_drop += metric_all[i].drop_count;
			if (metric_all[i].fifo_peak > max_peak) {
				max_peak = metric_all[i].fifo_peak;
			}
		}
		printf("metrics: tx=%" PRIu64 " rx=%" PRIu64 " local=%" PRIu64 " drops=%" PRIu64
		       " fifo_peak=%" PRIu64 "\n",
		    total_tx, total_rx, total_local, total_drop, max_peak);
	}

	for (i = 0; i < chip_count; i++) {
		int status = 0;
		if (child_pids[i] <= 0) {
			continue;
		}
		if (waitpid(child_pids[i], &status, 0) < 0) {
			perror("waitpid");
			goto fail;
		}
		if (!(WIFEXITED(status) && WEXITSTATUS(status) == 0)) {
			fprintf(stderr, "chip pid=%ld exited abnormally (status=%d)\n", (long) child_pids[i],
			    status);
			goto fail;
		}
	}

	printf("orchestrator: all %d chips exited cleanly\n", chip_count);

	nng_socket_close(metric_pull);
	nng_socket_close(done_pull);
	nng_socket_close(clock_pub);
	free(metric_all);
	free(done_latest);
	free(child_pids);
	free(out_ids);
	free(input_ids);
	nng_fini();
	return 0;

fail:
	if (child_pids != NULL) {
		terminate_children(child_pids, chip_count);
		for (i = 0; i < chip_count; i++) {
			if (child_pids[i] > 0) {
				waitpid(child_pids[i], NULL, 0);
			}
		}
	}
	if (nng_socket_id(metric_pull) > 0) {
		nng_socket_close(metric_pull);
	}
	if (nng_socket_id(done_pull) > 0) {
		nng_socket_close(done_pull);
	}
	if (nng_socket_id(clock_pub) > 0) {
		nng_socket_close(clock_pub);
	}
	free(metric_all);
	free(done_latest);
	free(child_pids);
	free(out_ids);
	free(input_ids);
	nng_fini();
	return 1;
}
