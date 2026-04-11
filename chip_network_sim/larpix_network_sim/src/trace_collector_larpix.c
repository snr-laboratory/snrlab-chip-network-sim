#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <inttypes.h>
#include <nng/nng.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "larpixsim/trace_protocol.h"

static void usage(const char *prog) {
    fprintf(stderr,
        "Usage: %s -listen_url <URI> -out <path> -expected_senders <N> [options]\n"
        "Options:\n"
        "  -recv_timeout_ms <N>  recv timeout while waiting for finish events (default 5000)\n",
        prog);
}

typedef struct {
    const char *listen_url;
    const char *out_path;
    int expected_senders;
    int recv_timeout_ms;
} options_t;

static int parse_int(const char *value, int *out) {
    long v;
    char *end;
    errno = 0;
    v = strtol(value, &end, 10);
    if (errno != 0 || end == value || *end != '\0' || v < INT32_MIN || v > INT32_MAX) return -1;
    *out = (int)v;
    return 0;
}

static int parse_args(int argc, char **argv, options_t *opts) {
    int i;
    memset(opts, 0, sizeof(*opts));
    opts->recv_timeout_ms = 5000;
    for (i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "-listen_url") == 0 && i + 1 < argc) {
            opts->listen_url = argv[++i];
        } else if (strcmp(argv[i], "-out") == 0 && i + 1 < argc) {
            opts->out_path = argv[++i];
        } else if (strcmp(argv[i], "-expected_senders") == 0 && i + 1 < argc) {
            if (parse_int(argv[++i], &opts->expected_senders) != 0 || opts->expected_senders <= 0) return -1;
        } else if (strcmp(argv[i], "-recv_timeout_ms") == 0 && i + 1 < argc) {
            if (parse_int(argv[++i], &opts->recv_timeout_ms) != 0 || opts->recv_timeout_ms <= 0) return -1;
        } else {
            return -1;
        }
    }
    return (opts->listen_url != NULL && opts->out_path != NULL && opts->expected_senders > 0) ? 0 : -1;
}

static const char *event_name(uint8_t event_type) {
    switch (event_type) {
    case LARPIXSIM_TRACE_EVENT_CHARGE_INJECTED: return "charge_injected";
    case LARPIXSIM_TRACE_EVENT_RX_PACKET: return "rx_packet";
    case LARPIXSIM_TRACE_EVENT_TX_PACKET: return "tx_packet";
    case LARPIXSIM_TRACE_EVENT_FINISH: return "finish";
    default: return "unknown";
    }
}

static const char *edge_name(uint8_t edge) {
    switch (edge) {
    case 0: return "north";
    case 1: return "east";
    case 2: return "south";
    case 3: return "west";
    default: return "unknown";
    }
}

static int finish_seen(uint32_t *runtime_ids, int count, uint32_t id) {
    int i;
    for (i = 0; i < count; ++i) if (runtime_ids[i] == id) return 1;
    return 0;
}

int main(int argc, char **argv) {
    options_t opts;
    nng_socket pull = NNG_SOCKET_INITIALIZER;
    FILE *out = NULL;
    int rv;
    uint32_t *finished = NULL;
    int finished_count = 0;
    int exit_code = 1;

    if (nng_init(NULL) != 0) {
        fprintf(stderr, "trace_collector_larpix: nng_init failed\n");
        return 1;
    }

    if (parse_args(argc, argv, &opts) != 0) {
        usage(argv[0]);
        nng_fini();
        return 2;
    }

    out = fopen(opts.out_path, "w");
    if (out == NULL) {
        perror("fopen(trace out)");
        return 1;
    }

    finished = (uint32_t *)calloc((size_t)opts.expected_senders, sizeof(uint32_t));
    if (finished == NULL) {
        perror("calloc");
        goto cleanup;
    }

    rv = nng_pull0_open(&pull);
    if (rv != 0) {
        fprintf(stderr, "trace_collector_larpix: pull open failed: %s\n", nng_strerror((nng_err)rv));
        goto cleanup;
    }
    rv = nng_listen(pull, opts.listen_url, NULL, 0);
    if (rv != 0) {
        fprintf(stderr, "trace_collector_larpix: listen failed at %s: %s\n", opts.listen_url, nng_strerror((nng_err)rv));
        goto cleanup;
    }
    rv = nng_socket_set_ms(pull, NNG_OPT_RECVTIMEO, opts.recv_timeout_ms);
    if (rv != 0) {
        fprintf(stderr, "trace_collector_larpix: set recv timeout failed: %s\n", nng_strerror((nng_err)rv));
        goto cleanup;
    }

    while (finished_count < opts.expected_senders) {
        larpixsim_trace_event_msg_t msg;
        size_t msg_sz = sizeof(msg);
        rv = nng_recv(pull, &msg, &msg_sz, 0);
        if (rv != 0) {
            fprintf(stderr, "trace_collector_larpix: recv failed waiting for %d/%d finish events: %s\n",
                finished_count, opts.expected_senders, nng_strerror((nng_err)rv));
            goto cleanup;
        }
        if (msg_sz != sizeof(msg) || msg.type != LARPIXSIM_TRACE_MSG_EVENT) {
            continue;
        }

        fprintf(out,
            "{\"runtime_id\":%u,\"seq\":%" PRIu64 ",\"event\":\"%s\",\"edge\":\"%s\",\"channel\":%u,\"packet_word\":\"0x%016" PRIx64 "\",\"value_u32\":%u,\"value_f64\":%.17g}\n",
            msg.runtime_id,
            msg.seq,
            event_name(msg.event_type),
            edge_name(msg.edge),
            msg.channel,
            msg.packet_word,
            msg.value_u32,
            msg.value_f64);
        fflush(out);

        if (msg.event_type == LARPIXSIM_TRACE_EVENT_FINISH && !finish_seen(finished, finished_count, msg.runtime_id)) {
            finished[finished_count++] = msg.runtime_id;
        }
    }

    exit_code = 0;
cleanup:
    if (nng_socket_id(pull) > 0) nng_socket_close(pull);
    free(finished);
    if (out != NULL) fclose(out);
    nng_fini();
    return exit_code;
}
