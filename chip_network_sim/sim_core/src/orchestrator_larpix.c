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
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#include "chipsim/protocol.h"

static const char *
default_peer_binary_path(const char *argv0, const char *name, char *buf, size_t buf_len)
{
    const char *slash = strrchr(argv0, '/');
    int n;

    if (slash == NULL) {
        return name;
    }
    n = snprintf(buf, buf_len, "%.*s/%s", (int)(slash - argv0), argv0, name);
    if (n < 0 || (size_t)n >= buf_len) {
        return name;
    }
    return buf;
}

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
    nng_socket  req;
    nng_aio    *aio;
    _Atomic int connected;
} control_peer_t;

typedef struct {
    int         rows;
    int         cols;
    uint64_t    ticks;
    int         startup_ms;
    int         ack_timeout_ms;
    int         control_resend_ms;
    uint32_t    seed;
    const char *chip_bin;
    const char *fpga_bin;
    const char *backend;
    const char *stimulus_json;
    const char *startup_json;
    const char *init_regs_json;
    const char *trace_collector_bin;
    const char *trace_out;
    const char *occupancy_csv;
    int         occupancy_runtime_id;
    uint64_t    occupancy_tick_start;
    const char *rx_debug_csv;
    int         rx_debug_runtime_id;
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
        "  -control_resend_ms <N>  resend unanswered control requests (default 100)\n"
        "  -seed <N>               base seed (default 1)\n"
        "  -chip_bin <path>        chip executable (default ./larpix_chip)\n"
        "  -fpga_bin <path>        FPGA/controller executable (default ./fpga_larpix)\n"
        "  -backend <name>         chip backend (default cosim)\n"
        "  -stimulus_json <path>   charge stimulus JSON passed to each chip\n"
        "  -startup_json <path>    compiled startup schedule JSON passed to the FPGA controller\n"
        "  -init_regs_json <path>  optional RTL register preload JSON passed to each chip\n"
        "  -trace_collector_bin <path> trace collector executable (default ./trace_collector_larpix)\n"
        "  -trace_out <path>       optional per-tick trace event JSONL output\n"
        "  -occupancy_csv <path>   write chip occupancy CSV for one runtime\n"
        "  -occupancy_runtime_id <N> runtime_id that writes occupancy CSV\n"
        "  -occupancy_tick_start <N> first tick included in occupancy CSV\n"
        "  -rx_debug_csv <path>    write RX/Hydra debug CSV for one runtime\n"
        "  -rx_debug_runtime_id <N> runtime_id that writes RX debug CSV\n"
        "  -source_x <N>           source-chip x coordinate (default 0)\n"
        "  -source_y <N>           source-chip y coordinate (default 0)\n"
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
    static char default_chip_bin[512];
    static char default_fpga_bin[512];
    static char default_trace_collector_bin[512];

    memset(opts, 0, sizeof(*opts));
    opts->startup_ms = 350;
    opts->ack_timeout_ms = 5000;
    opts->control_resend_ms = 100;
    opts->seed = 1u;
    opts->chip_bin = default_peer_binary_path(argv[0], "chip_larpix", default_chip_bin, sizeof(default_chip_bin));
    opts->fpga_bin = default_peer_binary_path(argv[0], "fpga_larpix", default_fpga_bin, sizeof(default_fpga_bin));
    opts->backend = "cosim";
    opts->stimulus_json = NULL;
    opts->startup_json = NULL;
    opts->init_regs_json = NULL;
    opts->trace_collector_bin = default_peer_binary_path(argv[0], "trace_collector_larpix", default_trace_collector_bin, sizeof(default_trace_collector_bin));
    opts->trace_out = NULL;
    opts->occupancy_csv = NULL;
    opts->occupancy_runtime_id = -1;
    opts->occupancy_tick_start = 0;
    opts->rx_debug_csv = NULL;
    opts->rx_debug_runtime_id = -1;
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
        } else if (strcmp(argv[i], "-control_resend_ms") == 0 && i + 1 < argc) {
            if (parse_int(argv[++i], &opts->control_resend_ms) != 0 ||
                    opts->control_resend_ms <= 0) {
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
        } else if (strcmp(argv[i], "-init_regs_json") == 0 && i + 1 < argc) {
            opts->init_regs_json = argv[++i];
        } else if (strcmp(argv[i], "-trace_collector_bin") == 0 && i + 1 < argc) {
            opts->trace_collector_bin = argv[++i];
        } else if (strcmp(argv[i], "-trace_out") == 0 && i + 1 < argc) {
            opts->trace_out = argv[++i];
        } else if (strcmp(argv[i], "-occupancy_csv") == 0 && i + 1 < argc) {
            opts->occupancy_csv = argv[++i];
        } else if (strcmp(argv[i], "-occupancy_runtime_id") == 0 && i + 1 < argc) {
            if (parse_int(argv[++i], &opts->occupancy_runtime_id) != 0) {
                return -1;
            }
        } else if (strcmp(argv[i], "-occupancy_tick_start") == 0 && i + 1 < argc) {
            if (parse_u64(argv[++i], &opts->occupancy_tick_start) != 0) {
                return -1;
            }
        } else if (strcmp(argv[i], "-rx_debug_csv") == 0 && i + 1 < argc) {
            opts->rx_debug_csv = argv[++i];
        } else if (strcmp(argv[i], "-rx_debug_runtime_id") == 0 && i + 1 < argc) {
            if (parse_int(argv[++i], &opts->rx_debug_runtime_id) != 0) {
                return -1;
            }
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
    return 0;
}

static int
build_endpoints(const orchestrator_larpix_options_t *opts,
    int runtime_count,
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
    *edge_port_base = *control_port_base + runtime_count + 16;
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
    const char *trace_url,
    const char *edge_prefix,
    int edge_port_base,
    pid_t *child_pid)
{
    pid_t pid;
    char id_s[32], seed_s[32], timeout_s[32];
    char north_in[128], east_in[128], south_in[128], west_in[128];
    char north_out[128], east_out[128], south_out[128], west_out[128];
    char occupancy_tick_start_s[32];
    char *argv_exec[64];
    int idx = 0;
    const bool attach_fpga = ((opts->startup_json != NULL || opts->init_regs_json != NULL) && runtime_id == source_chip_id);

    snprintf(id_s, sizeof(id_s), "%d", runtime_id);
    snprintf(seed_s, sizeof(seed_s), "%u", (unsigned)(opts->seed + (uint32_t)runtime_id));
    snprintf(timeout_s, sizeof(timeout_s), "%d", opts->ack_timeout_ms);
    snprintf(occupancy_tick_start_s, sizeof(occupancy_tick_start_s), "%" PRIu64, opts->occupancy_tick_start);

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
    if (opts->init_regs_json != NULL) {
        argv_exec[idx++] = "-init_regs_json";
        argv_exec[idx++] = (char *)opts->init_regs_json;
    }
    if (trace_url != NULL) {
        argv_exec[idx++] = "-trace_url";
        argv_exec[idx++] = (char *)trace_url;
    }
    if (opts->occupancy_csv != NULL && opts->occupancy_runtime_id == runtime_id) {
        argv_exec[idx++] = "-occupancy_csv";
        argv_exec[idx++] = (char *)opts->occupancy_csv;
        argv_exec[idx++] = "-occupancy_tick_start";
        argv_exec[idx++] = occupancy_tick_start_s;
    }
    if (opts->rx_debug_csv != NULL && opts->rx_debug_runtime_id == runtime_id) {
        argv_exec[idx++] = "-rx_debug_csv";
        argv_exec[idx++] = (char *)opts->rx_debug_csv;
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
launch_trace_collector(const orchestrator_larpix_options_t *opts,
    const char *trace_url,
    int expected_senders,
    pid_t *child_pid)
{
    pid_t pid;
    char expected_s[32];
    char timeout_s[32];
    char *argv_exec[12];
    int idx = 0;

    snprintf(expected_s, sizeof(expected_s), "%d", expected_senders);
    snprintf(timeout_s, sizeof(timeout_s), "%d", opts->ack_timeout_ms);

    argv_exec[idx++] = (char *)opts->trace_collector_bin;
    argv_exec[idx++] = "-listen_url";
    argv_exec[idx++] = (char *)trace_url;
    argv_exec[idx++] = "-out";
    argv_exec[idx++] = (char *)opts->trace_out;
    argv_exec[idx++] = "-expected_senders";
    argv_exec[idx++] = expected_s;
    argv_exec[idx++] = "-recv_timeout_ms";
    argv_exec[idx++] = timeout_s;
    argv_exec[idx++] = NULL;

    pid = fork();
    if (pid < 0) {
        perror("fork");
        return -1;
    }
    if (pid == 0) {
        execvp(opts->trace_collector_bin, argv_exec);
        perror("execvp(trace_collector_larpix)");
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

static void
control_pipe_event(nng_pipe pipe, nng_pipe_ev event, void *arg)
{
    control_peer_t *peer = (control_peer_t *)arg;
    (void)pipe;

    if (event == NNG_PIPE_EV_ADD_POST) {
        atomic_fetch_add_explicit(&peer->connected, 1, memory_order_relaxed);
    } else if (event == NNG_PIPE_EV_REM_POST) {
        atomic_fetch_sub_explicit(&peer->connected, 1, memory_order_relaxed);
    }
}

static void
report_child_status(int runtime_id, pid_t pid)
{
    int status = 0;
    pid_t wait_rv;

    if (pid <= 0) {
        return;
    }
    wait_rv = waitpid(pid, &status, WNOHANG);
    if (wait_rv != pid) {
        return;
    }
    if (WIFEXITED(status)) {
        fprintf(stderr, "orchestrator_larpix runtime=%d pid=%ld exited with status=%d\n",
            runtime_id, (long)pid, WEXITSTATUS(status));
    } else if (WIFSIGNALED(status)) {
        fprintf(stderr, "orchestrator_larpix runtime=%d pid=%ld terminated by signal=%d\n",
            runtime_id, (long)pid, WTERMSIG(status));
    }
}

static int
wait_for_control_peers(control_peer_t *peers, int runtime_count,
    int timeout_ms, const pid_t *child_pids)
{
    const double deadline = mono_now_sec() + (double)timeout_ms / 1000.0;

    for (;;) {
        int connected = 0;
        int i;

        for (i = 0; i < runtime_count; ++i) {
            if (atomic_load_explicit(&peers[i].connected, memory_order_relaxed) > 0) {
                connected++;
            }
        }
        if (connected == runtime_count) {
            return 0;
        }
        if (mono_now_sec() >= deadline) {
            fprintf(stderr, "orchestrator_larpix timed out waiting for control peers: connected=%d expected=%d\n",
                connected, runtime_count);
            for (i = 0; i < runtime_count; ++i) {
                if (atomic_load_explicit(&peers[i].connected, memory_order_relaxed) <= 0) {
                    fprintf(stderr, "orchestrator_larpix missing control peer runtime=%d pid=%ld\n",
                        i, (long)child_pids[i]);
                }
                report_child_status(i, child_pids[i]);
            }
            return -1;
        }
        nng_msleep(1);
    }
}

static int
send_control_and_gather(control_peer_t *peers,
    const chipsim_tick_msg_t *control_msg,
    int runtime_count,
    int timeout_ms,
    const pid_t *child_pids)
{
    int failed = 0;
    int send_posted = 0;
    int i;

    /* Queue every request before waiting on any runtime. Each AIO belongs to
     * a dedicated REQ socket, so all control transactions can progress
     * concurrently without requests reaching the wrong process. */
    for (i = 0; i < runtime_count; ++i) {
        nng_msg *msg = NULL;
        int rv = nng_msg_alloc(&msg, sizeof(*control_msg));
        if (rv != 0) {
            fprintf(stderr, "orchestrator_larpix allocate control request for runtime=%d failed: %s\n",
                i, nng_strerror(rv));
            failed = 1;
            break;
        }
        memcpy(nng_msg_body(msg), control_msg, sizeof(*control_msg));
        nng_aio_set_timeout(peers[i].aio, timeout_ms);
        nng_aio_set_msg(peers[i].aio, msg);
        nng_socket_send(peers[i].req, peers[i].aio);
        send_posted++;
    }

    for (i = 0; i < send_posted; ++i) {
        int rv;
        nng_msg *msg;

        nng_aio_wait(peers[i].aio);
        rv = nng_aio_result(peers[i].aio);
        if (rv != 0) {
            fprintf(stderr, "orchestrator_larpix send(%s) failed for runtime=%d seq=%" PRIu64 ": %s\n",
                control_msg->type == CHIPSIM_MSG_STOP ? "STOP" : "TICK",
                i, control_msg->seq, nng_strerror(rv));
            msg = nng_aio_get_msg(peers[i].aio);
            if (msg != NULL) {
                nng_aio_set_msg(peers[i].aio, NULL);
                nng_msg_free(msg);
            }
            report_child_status(i, child_pids[i]);
            failed = 1;
        }
    }
    if (failed || send_posted != runtime_count) {
        return -1;
    }

    for (i = 0; i < runtime_count; ++i) {
        nng_aio_set_timeout(peers[i].aio, timeout_ms);
        nng_socket_recv(peers[i].req, peers[i].aio);
    }

    for (i = 0; i < runtime_count; ++i) {
        chipsim_done_msg_t done;
        nng_msg *msg;
        int rv;

        nng_aio_wait(peers[i].aio);
        rv = nng_aio_result(peers[i].aio);
        if (rv != 0) {
            fprintf(stderr, "orchestrator_larpix recv(DONE) failed for runtime=%d seq=%" PRIu64 ": %s\n",
                i, control_msg->seq, nng_strerror(rv));
            report_child_status(i, child_pids[i]);
            failed = 1;
            continue;
        }
        msg = nng_aio_get_msg(peers[i].aio);
        if (msg == NULL || nng_msg_len(msg) != sizeof(done)) {
            fprintf(stderr, "orchestrator_larpix received malformed DONE from runtime=%d\n", i);
            if (msg != NULL) {
                nng_aio_set_msg(peers[i].aio, NULL);
                nng_msg_free(msg);
            }
            failed = 1;
            continue;
        }
        memcpy(&done, nng_msg_body(msg), sizeof(done));
        nng_aio_set_msg(peers[i].aio, NULL);
        nng_msg_free(msg);

        if (done.type != CHIPSIM_MSG_DONE || done.chip_id != (uint32_t)i ||
                done.seq != control_msg->seq) {
            fprintf(stderr, "orchestrator_larpix DONE mismatch on runtime=%d: type=%u chip_id=%u seq=%" PRIu64
                " expected_seq=%" PRIu64 "\n",
                i, (unsigned)done.type, done.chip_id, done.seq, control_msg->seq);
            failed = 1;
        }
    }
    return failed ? -1 : 0;
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
    control_peer_t *control_peers = NULL;
    nng_socket metric_pull = NNG_SOCKET_INITIALIZER;
    char control_prefix[256];
    char control_url[256];
    char metric_url[256];
    char trace_url[256];
    char edge_prefix[256];
    int control_port_base = 0;
    int edge_port_base = 0;
    pid_t collector_pid = -1;
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
    use_fpga = (opts.startup_json != NULL || opts.init_regs_json != NULL);
    fpga_runtime_id = chip_count;
    runtime_count = chip_count + (use_fpga ? 1 : 0);

    routes = calloc((size_t)chip_count, sizeof(*routes));
    child_pids = calloc((size_t)runtime_count, sizeof(*child_pids));
    control_peers = calloc((size_t)runtime_count, sizeof(*control_peers));
    if (routes == NULL || child_pids == NULL || control_peers == NULL) {
        fprintf(stderr, "allocation failure\n");
        goto fail;
    }
    for (i = 0; i < runtime_count; ++i) {
        atomic_init(&control_peers[i].connected, 0);
    }

    build_default_routes(&opts, routes);

    if (build_endpoints(&opts, runtime_count, control_prefix, sizeof(control_prefix), metric_url, sizeof(metric_url),
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

    if (opts.trace_out != NULL) {
        if (snprintf(trace_url, sizeof(trace_url), "tcp://127.0.0.1:%d", control_port_base - 1) < 0) {
            goto fail;
        }
        if (launch_trace_collector(&opts, trace_url, chip_count, &collector_pid) != 0) {
            goto fail;
        }
    } else {
        trace_url[0] = '\0';
    }

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

    for (i = 0; i < runtime_count; ++i) {
        int resend_tick_ms = opts.control_resend_ms < 10
            ? opts.control_resend_ms : 10;

        if (build_endpoint_url(control_url, sizeof(control_url), control_prefix,
                control_port_base + i) != 0) {
            fprintf(stderr, "failed to build control endpoint for runtime=%d\n", i);
            goto fail;
        }
        rv = nng_req0_open(&control_peers[i].req);
        if (rv != 0) {
            fprintf(stderr, "control REQ open failed for runtime=%d: %s\n",
                i, nng_strerror(rv));
            goto fail;
        }
        rv = nng_socket_set_ms(control_peers[i].req,
            NNG_OPT_REQ_RESENDTIME, opts.control_resend_ms);
        if (rv != 0) {
            fprintf(stderr, "control resend-time setup failed for runtime=%d: %s\n",
                i, nng_strerror(rv));
            goto fail;
        }
        rv = nng_socket_set_ms(control_peers[i].req,
            NNG_OPT_REQ_RESENDTICK, resend_tick_ms);
        if (rv != 0) {
            fprintf(stderr, "control resend-tick setup failed for runtime=%d: %s\n",
                i, nng_strerror(rv));
            goto fail;
        }
        rv = nng_aio_alloc(&control_peers[i].aio, NULL, NULL);
        if (rv != 0) {
            fprintf(stderr, "control AIO allocation failed for runtime=%d: %s\n",
                i, nng_strerror(rv));
            goto fail;
        }
        rv = nng_pipe_notify(control_peers[i].req, NNG_PIPE_EV_ADD_POST,
            control_pipe_event, &control_peers[i]);
        if (rv != 0) {
            goto fail;
        }
        rv = nng_pipe_notify(control_peers[i].req, NNG_PIPE_EV_REM_POST,
            control_pipe_event, &control_peers[i]);
        if (rv != 0) {
            goto fail;
        }
        rv = nng_listen(control_peers[i].req, control_url, NULL, 0);
        if (rv != 0) {
            fprintf(stderr, "control REQ listen failed for runtime=%d at %s: %s\n",
                i, control_url, nng_strerror(rv));
            goto fail;
        }
    }

    for (i = 0; i < chip_count; i++) {
        if (build_endpoint_url(control_url, sizeof(control_url), control_prefix, control_port_base + i) != 0) {
            goto fail;
        }
        if (launch_chip(&opts, i, &routes[i], source_chip_id, fpga_runtime_id,
                control_url, metric_url, (opts.trace_out != NULL ? trace_url : NULL), edge_prefix, edge_port_base, &child_pids[i]) != 0) {
            goto fail;
        }
    }

    if (use_fpga) {
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

    if (wait_for_control_peers(control_peers,
            runtime_count, opts.ack_timeout_ms, child_pids) != 0) {
        goto fail;
    }
    printf("orchestrator_larpix: control_req_rep_connected=%d\n", runtime_count);
    printf("orchestrator_larpix: tick_dispatch=aio_req_rep resend_ms=%d\n",
        opts.control_resend_ms);

    for (seq = 0; seq < opts.ticks; seq++) {
        chipsim_tick_msg_t tick;
        memset(&tick, 0, sizeof(tick));
        tick.type = CHIPSIM_MSG_TICK;
        tick.seq = seq;

        if (send_control_and_gather(control_peers, &tick,
                runtime_count, opts.ack_timeout_ms, child_pids) != 0) {
            goto fail;
        }
    }

    {
        chipsim_tick_msg_t stop_msg;
        memset(&stop_msg, 0, sizeof(stop_msg));
        stop_msg.type = CHIPSIM_MSG_STOP;
        stop_msg.seq = opts.ticks;

        if (send_control_and_gather(control_peers, &stop_msg,
                runtime_count, opts.ack_timeout_ms, child_pids) != 0) {
            goto fail;
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
    if (collector_pid > 0) {
        int status = 0;
        waitpid(collector_pid, &status, 0);
    }

    t_all_end = mono_now_sec();
    printf("orchestrator_larpix: completed in %.6f sec\n", t_all_end - t_all_start);

    for (i = 0; i < runtime_count; ++i) {
        if (control_peers[i].aio != NULL) {
            nng_aio_stop(control_peers[i].aio);
            nng_aio_free(control_peers[i].aio);
        }
        if (nng_socket_id(control_peers[i].req) > 0) {
            nng_socket_close(control_peers[i].req);
        }
    }
    if (nng_socket_id(metric_pull) > 0) {
        nng_socket_close(metric_pull);
    }
    free(routes);
    free(child_pids);
    free(control_peers);
    nng_fini();
    return 0;

fail:
    if (child_pids != NULL) {
        terminate_children(child_pids, runtime_count);
    }
    if (collector_pid > 0) {
        kill(collector_pid, SIGTERM);
    }
    if (control_peers != NULL) {
        for (i = 0; i < runtime_count; ++i) {
            if (control_peers[i].aio != NULL) {
                nng_aio_stop(control_peers[i].aio);
                nng_aio_free(control_peers[i].aio);
            }
            if (nng_socket_id(control_peers[i].req) > 0) {
                nng_socket_close(control_peers[i].req);
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
    if (collector_pid > 0) {
        int status = 0;
        waitpid(collector_pid, &status, 0);
    }
    free(routes);
    free(child_pids);
    free(control_peers);
    nng_fini();
    return 1;
}
