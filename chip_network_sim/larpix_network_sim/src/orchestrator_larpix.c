/*
 * orchestrator_larpix.c
 *
 * LArPix-specific orchestrator for the 4-edge serial-bit network model. It
 * launches one chip process per chip plus an optional fpga_larpix controller,
 * wires the source chip's south edge to that controller for startup packet
 * injection, and advances all runtimes in strict TICK/DONE lock-step.
 */

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
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#include "chipsim/protocol.h"

typedef enum {
    LARPIX_EDGE_NORTH = 0,
    LARPIX_EDGE_EAST  = 1,
    LARPIX_EDGE_SOUTH = 2,
    LARPIX_EDGE_WEST  = 3,
    LARPIX_EDGE_COUNT = 4,
} larpix_edge_t;

typedef struct {
    int neighbor[LARPIX_EDGE_COUNT];
} larpix_route_t;

typedef struct {
    int         rows;
    int         cols;
    uint64_t    ticks;
    int         startup_ms;
    int         ack_timeout_ms;
    uint32_t    seed;
    const char *chip_bin;
    const char *fpga_bin;
    const char *backend;
    const char *stimulus_json;
    const char *startup_json;
    const char *base_uri;
    int         source_x;
    int         source_y;
} orchestrator_larpix_options_t;

static double
mono_now_sec(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + ((double)ts.tv_nsec / 1.0e9);
}

static void
usage(const char *prog)
{
    fprintf(stderr,
        "Usage: %s -rows <R> -cols <C> -ticks <N> [options]\n"
        "Options:\n"
        "  -startup_ms <N>         wait before first tick (default 350)\n"
        "  -ack_timeout_ms <N>     timeout waiting for DONE/METRIC (default 5000)\n"
        "  -seed <N>               base seed (default 1)\n"
        "  -chip_bin <path>        chip executable (default ./larpix_chip)\n"
        "  -fpga_bin <path>        FPGA/controller executable (default ./fpga_larpix)\n"
        "  -backend <name>         chip backend (default cosim)\n"
        "  -stimulus_json <path>   charge stimulus JSON passed to each chip\n"
        "  -startup_json <path>    compiled startup schedule JSON passed to the FPGA controller\n"
        "  -source_x <N>           source-chip x coordinate on bottom row (default 0)\n"
        "  -source_y <N>           source-chip y coordinate (default 0, must be 0 when startup_json is used)\n"
        "  -base_uri <tcp://127.0.0.1:PORT> endpoint base port (default unique per run)\n",
        prog);
}

static int
parse_int(const char *value, int *out)
{
    long v;
    char *end;

    errno = 0;
    v = strtol(value, &end, 10);
    if (errno != 0 || end == value || *end != '\0' || v < INT32_MIN || v > INT32_MAX) {
        return -1;
    }
    *out = (int)v;
    return 0;
}

static int
parse_u32(const char *value, uint32_t *out)
{
    unsigned long v;
    char *end;

    errno = 0;
    v = strtoul(value, &end, 10);
    if (errno != 0 || end == value || *end != '\0' || v > UINT32_MAX) {
        return -1;
    }
    *out = (uint32_t)v;
    return 0;
}

static int
parse_u64(const char *value, uint64_t *out)
{
    unsigned long long v;
    char *end;

    errno = 0;
    v = strtoull(value, &end, 10);
    if (errno != 0 || end == value || *end != '\0') {
        return -1;
    }
    *out = (uint64_t)v;
    return 0;
}

static int
parse_args(int argc, char **argv, orchestrator_larpix_options_t *opts)
{
    int i;

    memset(opts, 0, sizeof(*opts));
    opts->startup_ms = 350;
    opts->ack_timeout_ms = 5000;
    opts->seed = 1u;
    opts->chip_bin = "./larpix_chip";
    opts->fpga_bin = "./fpga_larpix";
    opts->backend = "cosim";
    opts->stimulus_json = NULL;
    opts->startup_json = NULL;
    opts->base_uri = NULL;
    opts->source_x = 0;
    opts->source_y = 0;

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
        } else if (strcmp(argv[i], "-startup_ms") == 0 && i + 1 < argc) {
            if (parse_int(argv[++i], &opts->startup_ms) != 0 || opts->startup_ms < 0) {
                return -1;
            }
        } else if (strcmp(argv[i], "-ack_timeout_ms") == 0 && i + 1 < argc) {
            if (parse_int(argv[++i], &opts->ack_timeout_ms) != 0 || opts->ack_timeout_ms <= 0) {
                return -1;
            }
        } else if (strcmp(argv[i], "-seed") == 0 && i + 1 < argc) {
            if (parse_u32(argv[++i], &opts->seed) != 0) {
                return -1;
            }
        } else if (strcmp(argv[i], "-chip_bin") == 0 && i + 1 < argc) {
            opts->chip_bin = argv[++i];
        } else if (strcmp(argv[i], "-fpga_bin") == 0 && i + 1 < argc) {
            opts->fpga_bin = argv[++i];
        } else if (strcmp(argv[i], "-backend") == 0 && i + 1 < argc) {
            opts->backend = argv[++i];
        } else if (strcmp(argv[i], "-stimulus_json") == 0 && i + 1 < argc) {
            opts->stimulus_json = argv[++i];
        } else if (strcmp(argv[i], "-startup_json") == 0 && i + 1 < argc) {
            opts->startup_json = argv[++i];
        } else if (strcmp(argv[i], "-base_uri") == 0 && i + 1 < argc) {
            opts->base_uri = argv[++i];
        } else if (strcmp(argv[i], "-source_x") == 0 && i + 1 < argc) {
            if (parse_int(argv[++i], &opts->source_x) != 0) {
                return -1;
            }
        } else if (strcmp(argv[i], "-source_y") == 0 && i + 1 < argc) {
            if (parse_int(argv[++i], &opts->source_y) != 0) {
                return -1;
            }
        } else {
            return -1;
        }
    }

    if (!(opts->rows > 0 && opts->cols > 0 && opts->ticks > 0)) {
        return -1;
    }
    if (opts->source_x < 0 || opts->source_x >= opts->cols || opts->source_y < 0 || opts->source_y >= opts->rows) {
        return -1;
    }
    if (opts->startup_json != NULL && opts->source_y != 0) {
        fprintf(stderr, "source_y must be 0 when an FPGA startup source is used\n");
        return -1;
    }
    return 0;
}

static int
build_endpoints(const orchestrator_larpix_options_t *opts,
    char *control_prefix, size_t control_prefix_len,
    char *metric_url, size_t metric_len,
    char *edge_prefix, size_t edge_prefix_len,
    int *control_port_base, int *edge_port_base)
{
    int base_port = 0;
    int n;
    const char tcp_prefix[] = "tcp://127.0.0.1:";

    if (opts->base_uri != NULL) {
        const char *start = NULL;
        if (strncmp(opts->base_uri, tcp_prefix, strlen(tcp_prefix)) != 0) {
            fprintf(stderr, "base_uri must look like tcp://127.0.0.1:<port>\n");
            return -1;
        }
        start = opts->base_uri + (int)strlen(tcp_prefix);
        if (parse_int(start, &base_port) != 0) {
            fprintf(stderr, "invalid base_uri port in %s\n", opts->base_uri);
            return -1;
        }
    } else {
        struct timespec ts;
        uint64_t mix;
        clock_gettime(CLOCK_REALTIME, &ts);
        mix = ((uint64_t)ts.tv_sec * 1000000000ull) ^ (uint64_t)ts.tv_nsec ^ (uint64_t)getpid();
        /* Reserve a reasonably large port block for one run. */
        base_port = 30000 + (int)(mix % 20000ull);
    }

    n = snprintf(control_prefix, control_prefix_len, "tcp://127.0.0.1:%%d");
    if (n < 0 || (size_t)n >= control_prefix_len) {
        return -1;
    }
    n = snprintf(metric_url, metric_len, "tcp://127.0.0.1:%d", base_port + 2);
    if (n < 0 || (size_t)n >= metric_len) {
        return -1;
    }
    n = snprintf(edge_prefix, edge_prefix_len, "tcp://127.0.0.1:%%d");
    if (n < 0 || (size_t)n >= edge_prefix_len) {
        return -1;
    }

    *control_port_base = base_port + 10;
    *edge_port_base = base_port + 100;
    return 0;
}

static int
build_endpoint_url(char *dst, size_t dst_len, const char *prefix, int port)
{
    int n;
    if (strstr(prefix, "%d") != NULL) {
        n = snprintf(dst, dst_len, prefix, port);
    } else {
        n = snprintf(dst, dst_len, "%s%d", prefix, port);
    }
    if (n < 0 || (size_t)n >= dst_len) {
        return -1;
    }
    return 0;
}

static int
chip_id_from_xy(int x, int y, int cols)
{
    return y * cols + x;
}

static void
build_default_routes(const orchestrator_larpix_options_t *opts, larpix_route_t *routes)
{
    int x, y;

    for (y = 0; y < opts->rows; y++) {
        for (x = 0; x < opts->cols; x++) {
            const int id = chip_id_from_xy(x, y, opts->cols);
            routes[id].neighbor[LARPIX_EDGE_NORTH] = (y + 1 < opts->rows) ? chip_id_from_xy(x, y + 1, opts->cols) : -1;
            routes[id].neighbor[LARPIX_EDGE_EAST]  = (x + 1 < opts->cols) ? chip_id_from_xy(x + 1, y, opts->cols) : -1;
            routes[id].neighbor[LARPIX_EDGE_SOUTH] = (y > 0) ? chip_id_from_xy(x, y - 1, opts->cols) : -1;
            routes[id].neighbor[LARPIX_EDGE_WEST]  = (x > 0) ? chip_id_from_xy(x - 1, y, opts->cols) : -1;
        }
    }
}

static int
edge_output_port(int edge_port_base, int runtime_id, int edge)
{
    return edge_port_base + runtime_id * LARPIX_EDGE_COUNT + edge;
}

static int
launch_chip(const orchestrator_larpix_options_t *opts,
    int runtime_id,
    const larpix_route_t *route,
    int source_chip_id,
    int fpga_runtime_id,
    const char *control_url,
    const char *metric_url,
    const char *edge_prefix,
    int edge_port_base,
    pid_t *child_pid)
{
    pid_t pid;
    char id_s[32], seed_s[32], timeout_s[32];
    char north_in[128], east_in[128], south_in[128], west_in[128];
    char north_out[128], east_out[128], south_out[128], west_out[128];
    char *argv_exec[46];
    int idx = 0;
    const bool attach_fpga = (opts->startup_json != NULL && runtime_id == source_chip_id);

    snprintf(id_s, sizeof(id_s), "%d", runtime_id);
    snprintf(seed_s, sizeof(seed_s), "%u", (unsigned)(opts->seed + (uint32_t)runtime_id));
    snprintf(timeout_s, sizeof(timeout_s), "%d", opts->ack_timeout_ms);

    if (build_endpoint_url(north_out, sizeof(north_out), edge_prefix,
            edge_output_port(edge_port_base, runtime_id, LARPIX_EDGE_NORTH)) != 0 ||
        build_endpoint_url(east_out, sizeof(east_out), edge_prefix,
            edge_output_port(edge_port_base, runtime_id, LARPIX_EDGE_EAST)) != 0 ||
        build_endpoint_url(south_out, sizeof(south_out), edge_prefix,
            edge_output_port(edge_port_base, runtime_id, LARPIX_EDGE_SOUTH)) != 0 ||
        build_endpoint_url(west_out, sizeof(west_out), edge_prefix,
            edge_output_port(edge_port_base, runtime_id, LARPIX_EDGE_WEST)) != 0) {
        return -1;
    }

    if (route->neighbor[LARPIX_EDGE_NORTH] >= 0) {
        if (build_endpoint_url(north_in, sizeof(north_in), edge_prefix,
                edge_output_port(edge_port_base, route->neighbor[LARPIX_EDGE_NORTH], LARPIX_EDGE_SOUTH)) != 0) {
            return -1;
        }
    } else {
        snprintf(north_in, sizeof(north_in), "-1");
    }
    if (route->neighbor[LARPIX_EDGE_EAST] >= 0) {
        if (build_endpoint_url(east_in, sizeof(east_in), edge_prefix,
                edge_output_port(edge_port_base, route->neighbor[LARPIX_EDGE_EAST], LARPIX_EDGE_WEST)) != 0) {
            return -1;
        }
    } else {
        snprintf(east_in, sizeof(east_in), "-1");
    }
    if (attach_fpga) {
        if (build_endpoint_url(south_in, sizeof(south_in), edge_prefix,
                edge_output_port(edge_port_base, fpga_runtime_id, LARPIX_EDGE_NORTH)) != 0) {
            return -1;
        }
    } else if (route->neighbor[LARPIX_EDGE_SOUTH] >= 0) {
        if (build_endpoint_url(south_in, sizeof(south_in), edge_prefix,
                edge_output_port(edge_port_base, route->neighbor[LARPIX_EDGE_SOUTH], LARPIX_EDGE_NORTH)) != 0) {
            return -1;
        }
    } else {
        snprintf(south_in, sizeof(south_in), "-1");
    }
    if (route->neighbor[LARPIX_EDGE_WEST] >= 0) {
        if (build_endpoint_url(west_in, sizeof(west_in), edge_prefix,
                edge_output_port(edge_port_base, route->neighbor[LARPIX_EDGE_WEST], LARPIX_EDGE_EAST)) != 0) {
            return -1;
        }
    } else {
        snprintf(west_in, sizeof(west_in), "-1");
    }

    argv_exec[idx++] = (char *)opts->chip_bin;
    argv_exec[idx++] = "-id";
    argv_exec[idx++] = id_s;
    argv_exec[idx++] = "-backend";
    argv_exec[idx++] = (char *)opts->backend;
    argv_exec[idx++] = "-clock_url";
    argv_exec[idx++] = (char *)control_url;
    argv_exec[idx++] = "-metric_url";
    argv_exec[idx++] = (char *)metric_url;
    argv_exec[idx++] = "-north_in_url";
    argv_exec[idx++] = north_in;
    argv_exec[idx++] = "-east_in_url";
    argv_exec[idx++] = east_in;
    argv_exec[idx++] = "-south_in_url";
    argv_exec[idx++] = south_in;
    argv_exec[idx++] = "-west_in_url";
    argv_exec[idx++] = west_in;
    argv_exec[idx++] = "-north_out_url";
    argv_exec[idx++] = north_out;
    argv_exec[idx++] = "-east_out_url";
    argv_exec[idx++] = east_out;
    argv_exec[idx++] = "-south_out_url";
    argv_exec[idx++] = south_out;
    argv_exec[idx++] = "-west_out_url";
    argv_exec[idx++] = west_out;
    argv_exec[idx++] = "-data_timeout_ms";
    argv_exec[idx++] = timeout_s;
    argv_exec[idx++] = "-seed";
    argv_exec[idx++] = seed_s;
    if (opts->stimulus_json != NULL) {
        argv_exec[idx++] = "-stimulus_json";
        argv_exec[idx++] = (char *)opts->stimulus_json;
    }
    argv_exec[idx++] = NULL;

    pid = fork();
    if (pid < 0) {
        perror("fork");
        return -1;
    }
    if (pid == 0) {
        execvp(opts->chip_bin, argv_exec);
        perror("execvp(larpix_chip)");
        _exit(127);
    }

    *child_pid = pid;
    return 0;
}

static int
launch_fpga(const orchestrator_larpix_options_t *opts,
    int fpga_runtime_id,
    int source_chip_id,
    const char *control_url,
    const char *metric_url,
    const char *edge_prefix,
    int edge_port_base,
    pid_t *child_pid)
{
    pid_t pid;
    char id_s[32], timeout_s[32];
    char north_in[128], north_out[128];
    char *argv_exec[20];
    int idx = 0;

    snprintf(id_s, sizeof(id_s), "%d", fpga_runtime_id);
    snprintf(timeout_s, sizeof(timeout_s), "%d", opts->ack_timeout_ms);

    if (build_endpoint_url(north_out, sizeof(north_out), edge_prefix,
            edge_output_port(edge_port_base, fpga_runtime_id, LARPIX_EDGE_NORTH)) != 0 ||
        build_endpoint_url(north_in, sizeof(north_in), edge_prefix,
            edge_output_port(edge_port_base, source_chip_id, LARPIX_EDGE_SOUTH)) != 0) {
        return -1;
    }

    argv_exec[idx++] = (char *)opts->fpga_bin;
    argv_exec[idx++] = "-id";
    argv_exec[idx++] = id_s;
    argv_exec[idx++] = "-clock_url";
    argv_exec[idx++] = (char *)control_url;
    argv_exec[idx++] = "-metric_url";
    argv_exec[idx++] = (char *)metric_url;
    argv_exec[idx++] = "-north_in_url";
    argv_exec[idx++] = north_in;
    argv_exec[idx++] = "-north_out_url";
    argv_exec[idx++] = north_out;
    argv_exec[idx++] = "-data_timeout_ms";
    argv_exec[idx++] = timeout_s;
    if (opts->startup_json != NULL) {
        argv_exec[idx++] = "-startup_json";
        argv_exec[idx++] = (char *)opts->startup_json;
    }
    argv_exec[idx++] = NULL;

    pid = fork();
    if (pid < 0) {
        perror("fork");
        return -1;
    }
    if (pid == 0) {
        execvp(opts->fpga_bin, argv_exec);
        perror("execvp(fpga_larpix)");
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
recv_done_response(nng_socket control_req, int expected_runtime_id, uint64_t expected_seq)
{
    chipsim_done_msg_t msg;
    size_t msg_sz = sizeof(msg);
    int rv;

    rv = nng_recv(control_req, &msg, &msg_sz, 0);
    if (rv != 0) {
        fprintf(stderr, "orchestrator_larpix recv(DONE) failed: %s\n", nng_strerror(rv));
        return -1;
    }
    if (msg_sz != sizeof(msg) || msg.type != CHIPSIM_MSG_DONE) {
        fprintf(stderr, "orchestrator_larpix received malformed DONE response\n");
        return -1;
    }
    if (msg.seq != expected_seq) {
        fprintf(stderr, "orchestrator_larpix received DONE seq=%" PRIu64 " expected=%" PRIu64 "\n",
            msg.seq, expected_seq);
        return -1;
    }
    if (msg.chip_id != (uint32_t)expected_runtime_id) {
        fprintf(stderr, "orchestrator_larpix received DONE chip_id=%u expected=%d\n",
            msg.chip_id, expected_runtime_id);
        return -1;
    }
    return 0;
}

int
main(int argc, char **argv)
{
    orchestrator_larpix_options_t opts;
    int chip_count;
    int runtime_count;
    int source_chip_id;
    int fpga_runtime_id;
    bool use_fpga;
    larpix_route_t *routes = NULL;
    pid_t *child_pids = NULL;
    nng_socket *control_reqs = NULL;
    nng_socket metric_pull = NNG_SOCKET_INITIALIZER;
    char control_prefix[256];
    char metric_url[256];
    char edge_prefix[256];
    int control_port_base = 0;
    int edge_port_base = 0;
    int rv;
    int i;
    uint64_t seq;
    nng_err init_err;
    double t_all_start;
    double t_all_end;

    t_all_start = mono_now_sec();
    init_err = nng_init(NULL);
    if (init_err != 0) {
        fprintf(stderr, "orchestrator_larpix nng_init failed: %s\n", nng_strerror((int)init_err));
        return 1;
    }

    if (parse_args(argc, argv, &opts) != 0) {
        usage(argv[0]);
        nng_fini();
        return 2;
    }

    chip_count = opts.rows * opts.cols;
    source_chip_id = chip_id_from_xy(opts.source_x, opts.source_y, opts.cols);
    use_fpga = (opts.startup_json != NULL);
    fpga_runtime_id = chip_count;
    runtime_count = chip_count + (use_fpga ? 1 : 0);

    routes = calloc((size_t)chip_count, sizeof(*routes));
    child_pids = calloc((size_t)runtime_count, sizeof(*child_pids));
    control_reqs = calloc((size_t)runtime_count, sizeof(*control_reqs));
    if (routes == NULL || child_pids == NULL || control_reqs == NULL) {
        fprintf(stderr, "allocation failure\n");
        goto fail;
    }

    build_default_routes(&opts, routes);

    if (build_endpoints(&opts, control_prefix, sizeof(control_prefix), metric_url, sizeof(metric_url),
            edge_prefix, sizeof(edge_prefix), &control_port_base, &edge_port_base) != 0) {
        fprintf(stderr, "failed to build endpoints\n");
        goto fail;
    }

    printf("orchestrator_larpix: rows=%d cols=%d chips=%d ticks=%" PRIu64 " backend=%s\n",
        opts.rows, opts.cols, chip_count, opts.ticks, opts.backend);
    printf("orchestrator_larpix: source=(%d,%d) source_chip_id=%d use_fpga=%d\n",
        opts.source_x, opts.source_y, source_chip_id, use_fpga ? 1 : 0);
    printf("orchestrator_larpix: control_prefix=%s control_port_base=%d edge_port_base=%d\n",
        control_prefix, control_port_base, edge_port_base);

    rv = nng_pull0_open(&metric_pull);
    if (rv != 0) {
        fprintf(stderr, "metric_pull open failed: %s\n", nng_strerror(rv));
        goto fail;
    }
    rv = nng_listen(metric_pull, metric_url, NULL, 0);
    if (rv != 0) {
        fprintf(stderr, "metric_pull listen failed at %s: %s\n", metric_url, nng_strerror(rv));
        goto fail;
    }
    rv = nng_socket_set_ms(metric_pull, NNG_OPT_RECVTIMEO, opts.ack_timeout_ms);
    if (rv != 0) {
        goto fail;
    }

    for (i = 0; i < chip_count; i++) {
        char control_url[256];
        if (build_endpoint_url(control_url, sizeof(control_url), control_prefix, control_port_base + i) != 0) {
            goto fail;
        }
        if (launch_chip(&opts, i, &routes[i], source_chip_id, fpga_runtime_id,
                control_url, metric_url, edge_prefix, edge_port_base, &child_pids[i]) != 0) {
            goto fail;
        }
    }

    if (use_fpga) {
        char control_url[256];
        if (build_endpoint_url(control_url, sizeof(control_url), control_prefix, control_port_base + fpga_runtime_id) != 0) {
            goto fail;
        }
        if (launch_fpga(&opts, fpga_runtime_id, source_chip_id,
                control_url, metric_url, edge_prefix, edge_port_base, &child_pids[fpga_runtime_id]) != 0) {
            goto fail;
        }
    }

    if (opts.startup_ms > 0) {
        struct timespec ts;
        ts.tv_sec = opts.startup_ms / 1000;
        ts.tv_nsec = (long)(opts.startup_ms % 1000) * 1000000L;
        nanosleep(&ts, NULL);
    }

    for (i = 0; i < runtime_count; i++) {
        char control_url[256];
        if (build_endpoint_url(control_url, sizeof(control_url), control_prefix, control_port_base + i) != 0) {
            goto fail;
        }
        rv = nng_req0_open(&control_reqs[i]);
        if (rv != 0) {
            fprintf(stderr, "control req open failed for runtime %d: %s\n", i, nng_strerror(rv));
            goto fail;
        }
        rv = nng_socket_set_ms(control_reqs[i], NNG_OPT_SENDTIMEO, opts.ack_timeout_ms);
        if (rv != 0) {
            goto fail;
        }
        rv = nng_socket_set_ms(control_reqs[i], NNG_OPT_RECVTIMEO, opts.ack_timeout_ms);
        if (rv != 0) {
            goto fail;
        }
        rv = nng_socket_set_ms(control_reqs[i], NNG_OPT_REQ_RESENDTIME, NNG_DURATION_INFINITE);
        if (rv != 0) {
            goto fail;
        }
        rv = nng_dial(control_reqs[i], control_url, NULL, 0);
        if (rv != 0) {
            fprintf(stderr, "control dial failed for runtime %d at %s: %s\n", i, control_url, nng_strerror(rv));
            goto fail;
        }
    }

    for (seq = 0; seq < opts.ticks; seq++) {
        chipsim_tick_msg_t tick;
        memset(&tick, 0, sizeof(tick));
        tick.type = CHIPSIM_MSG_TICK;
        tick.seq = seq;

        for (i = 0; i < runtime_count; i++) {
            rv = nng_send(control_reqs[i], &tick, sizeof(tick), 0);
            if (rv != 0) {
                fprintf(stderr, "send(TICK) failed for runtime %d: %s\n", i, nng_strerror(rv));
                goto fail;
            }
        }
        for (i = 0; i < runtime_count; i++) {
            if (recv_done_response(control_reqs[i], i, seq) != 0) {
                goto fail;
            }
        }
    }

    {
        chipsim_tick_msg_t stop_msg;
        memset(&stop_msg, 0, sizeof(stop_msg));
        stop_msg.type = CHIPSIM_MSG_STOP;
        stop_msg.seq = opts.ticks;

        for (i = 0; i < runtime_count; i++) {
            rv = nng_send(control_reqs[i], &stop_msg, sizeof(stop_msg), 0);
            if (rv != 0) {
                fprintf(stderr, "send(STOP) failed for runtime %d: %s\n", i, nng_strerror(rv));
                goto fail;
            }
        }
        for (i = 0; i < runtime_count; i++) {
            if (recv_done_response(control_reqs[i], i, opts.ticks) != 0) {
                goto fail;
            }
        }
    }

    for (i = 0; i < runtime_count; i++) {
        chipsim_metric_msg_t metric;
        size_t msg_sz = sizeof(metric);
        rv = nng_recv(metric_pull, &metric, &msg_sz, 0);
        if (rv != 0) {
            fprintf(stderr, "recv(METRIC) failed: %s\n", nng_strerror(rv));
            goto fail;
        }
    }

    for (i = 0; i < runtime_count; i++) {
        int status = 0;
        if (child_pids[i] > 0) {
            waitpid(child_pids[i], &status, 0);
        }
    }

    t_all_end = mono_now_sec();
    printf("orchestrator_larpix: completed in %.6f sec\n", t_all_end - t_all_start);

    for (i = 0; i < runtime_count; i++) {
        if (nng_socket_id(control_reqs[i]) > 0) {
            nng_socket_close(control_reqs[i]);
        }
    }
    if (nng_socket_id(metric_pull) > 0) {
        nng_socket_close(metric_pull);
    }
    free(routes);
    free(child_pids);
    free(control_reqs);
    nng_fini();
    return 0;

fail:
    if (child_pids != NULL) {
        terminate_children(child_pids, runtime_count);
    }
    if (control_reqs != NULL) {
        for (i = 0; i < runtime_count; i++) {
            if (nng_socket_id(control_reqs[i]) > 0) {
                nng_socket_close(control_reqs[i]);
            }
        }
    }
    if (nng_socket_id(metric_pull) > 0) {
        nng_socket_close(metric_pull);
    }
    if (child_pids != NULL) {
        for (i = 0; i < runtime_count; i++) {
            if (child_pids[i] > 0) {
                int status = 0;
                waitpid(child_pids[i], &status, 0);
            }
        }
    }
    free(routes);
    free(child_pids);
    free(control_reqs);
    nng_fini();
    return 1;
}
