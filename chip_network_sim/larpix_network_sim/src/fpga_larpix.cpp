#include <errno.h>
#include <inttypes.h>
#include <nng/nng.h>
#include <pthread.h>
#include <regex>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <string>
#include <vector>

#include "chipsim/protocol.h"

#define CHIPSIM_DEFAULT_CLOCK_URL "tcp://127.0.0.1:23000"
#define CHIPSIM_DEFAULT_METRIC_URL "tcp://127.0.0.1:23002"
#define CHIPSIM_DEFAULT_DATA_TIMEOUT_MS 5000
#define LARPIXSIM_MSG_BIT_PULL 101u
#define LARPIXSIM_MSG_BIT_REPLY 102u
#define LARPIXSIM_UART_FRAME_BITS 66u
#define ERRSTR(x) nng_strerror((nng_err)(x))

typedef struct {
    uint8_t  type;
    uint8_t  edge;
    uint8_t  reserved0[2];
    uint32_t requester_id;
    uint64_t seq;
} larpixsim_bit_pull_msg_t;

typedef struct {
    uint8_t  type;
    uint8_t  has_bit;
    uint8_t  edge;
    uint8_t  bit_value;
    uint32_t responder_id;
    uint64_t seq;
} larpixsim_bit_reply_msg_t;

typedef struct {
    uint64_t             tick_start;
    uint64_t             packet_word;
    std::string          label;
    std::vector<uint8_t> bits;
} scheduled_frame_t;

typedef struct {
    int         id;
    int         data_timeout_ms;
    const char *clock_url;
    const char *metric_url;
    const char *north_in_url;
    const char *north_out_url;
    const char *startup_json;
} fpga_options_t;

typedef struct {
    uint64_t tx_count;
    uint64_t rx_count;
    uint64_t decoded_packet_count;
    uint64_t last_seq;
} fpga_metrics_t;

typedef struct {
    pthread_mutex_t lock;
    pthread_cond_t  cond;
    bool            stop_requested;
    bool            has_published;
    uint64_t        seq;
    uint8_t         has_bit;
    uint8_t         bit_value;
    nng_socket      data_rep;
    int             fpga_id;
} bit_server_state_t;

struct uart_rx_state_t {
    bool                 active = false;
    std::vector<uint8_t> bits;
};

static void
usage(const char *prog)
{
    fprintf(stderr,
        "Usage: %s -id <id> -north_out_url <url> -north_in_url <url> -startup_json <compiled_json> [options]\n"
        "Options:\n"
        "  -clock_url <URI>       orchestrator control endpoint\n"
        "  -metric_url <URI>      orchestrator metric endpoint\n"
        "  -data_timeout_ms <N>   edge pull timeout (default 5000)\n",
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
parse_args(int argc, char **argv, fpga_options_t *opts)
{
    int i;

    memset(opts, 0, sizeof(*opts));
    opts->id              = -1;
    opts->data_timeout_ms = CHIPSIM_DEFAULT_DATA_TIMEOUT_MS;
    opts->clock_url       = CHIPSIM_DEFAULT_CLOCK_URL;
    opts->metric_url      = CHIPSIM_DEFAULT_METRIC_URL;

    for (i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-id") == 0 && i + 1 < argc) {
            if (parse_int(argv[++i], &opts->id) != 0) {
                return -1;
            }
        } else if (strcmp(argv[i], "-clock_url") == 0 && i + 1 < argc) {
            opts->clock_url = argv[++i];
        } else if (strcmp(argv[i], "-metric_url") == 0 && i + 1 < argc) {
            opts->metric_url = argv[++i];
        } else if (strcmp(argv[i], "-north_in_url") == 0 && i + 1 < argc) {
            opts->north_in_url = argv[++i];
        } else if (strcmp(argv[i], "-north_out_url") == 0 && i + 1 < argc) {
            opts->north_out_url = argv[++i];
        } else if (strcmp(argv[i], "-startup_json") == 0 && i + 1 < argc) {
            opts->startup_json = argv[++i];
        } else if (strcmp(argv[i], "-data_timeout_ms") == 0 && i + 1 < argc) {
            if (parse_int(argv[++i], &opts->data_timeout_ms) != 0 || opts->data_timeout_ms <= 0) {
                return -1;
            }
        } else {
            return -1;
        }
    }

    return (opts->id >= 0 && opts->north_in_url != NULL && opts->north_out_url != NULL &&
            opts->startup_json != NULL)
               ? 0
               : -1;
}

static int
send_done(nng_socket control_rep, const fpga_options_t *opts, uint64_t seq, const fpga_metrics_t *metrics)
{
    chipsim_done_msg_t done;
    int                rv;

    memset(&done, 0, sizeof(done));
    done.type            = CHIPSIM_MSG_DONE;
    done.chip_id         = (uint32_t) opts->id;
    done.seq             = seq;
    done.tx_count        = metrics->tx_count;
    done.rx_count        = metrics->rx_count;
    done.local_gen_count = metrics->decoded_packet_count;
    done.drop_count      = 0;
    done.fifo_occupancy  = 0;

    rv = nng_send(control_rep, &done, sizeof(done), 0);
    if (rv != 0) {
        fprintf(stderr, "fpga_larpix[%d] failed to send DONE: %s\n", opts->id, ERRSTR(rv));
        return -1;
    }
    return 0;
}

static int
send_metric(nng_socket metric_push, const fpga_options_t *opts, const fpga_metrics_t *metrics)
{
    chipsim_metric_msg_t msg;
    int                  rv;

    memset(&msg, 0, sizeof(msg));
    msg.type            = CHIPSIM_MSG_METRIC;
    msg.chip_id         = (uint32_t) opts->id;
    msg.seq             = metrics->last_seq;
    msg.tx_count        = metrics->tx_count;
    msg.rx_count        = metrics->rx_count;
    msg.local_gen_count = metrics->decoded_packet_count;
    msg.drop_count      = 0;
    msg.fifo_occupancy  = 0;
    msg.fifo_peak       = 0;

    rv = nng_send(metric_push, &msg, sizeof(msg), 0);
    if (rv != 0) {
        fprintf(stderr, "fpga_larpix[%d] failed to send METRIC: %s\n", opts->id, ERRSTR(rv));
        return -1;
    }
    return 0;
}

static int
bit_server_init(bit_server_state_t *state, nng_socket data_rep, int fpga_id)
{
    memset(state, 0, sizeof(*state));
    state->data_rep = data_rep;
    state->fpga_id  = fpga_id;
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
bit_server_destroy(bit_server_state_t *state)
{
    pthread_cond_destroy(&state->cond);
    pthread_mutex_destroy(&state->lock);
}

static void
bit_server_publish(bit_server_state_t *state, uint64_t seq, uint8_t has_bit, uint8_t bit_value)
{
    pthread_mutex_lock(&state->lock);
    state->has_published = true;
    state->seq           = seq;
    state->has_bit       = has_bit ? 1u : 0u;
    state->bit_value     = bit_value ? 1u : 0u;
    pthread_cond_broadcast(&state->cond);
    pthread_mutex_unlock(&state->lock);
}

static void
bit_server_request_stop(bit_server_state_t *state)
{
    pthread_mutex_lock(&state->lock);
    state->stop_requested = true;
    pthread_cond_broadcast(&state->cond);
    pthread_mutex_unlock(&state->lock);
}

static void *
bit_server_thread_main(void *arg)
{
    bit_server_state_t *state = (bit_server_state_t *) arg;

    for (;;) {
        larpixsim_bit_pull_msg_t  req;
        larpixsim_bit_reply_msg_t rep;
        size_t                   req_sz = sizeof(req);
        int                      rv;

        rv = nng_recv(state->data_rep, &req, &req_sz, 0);
        if (rv != 0) {
            break;
        }
        if (req_sz != sizeof(req) || req.type != LARPIXSIM_MSG_BIT_PULL || req.edge != 0) {
            continue;
        }

        memset(&rep, 0, sizeof(rep));
        rep.type         = LARPIXSIM_MSG_BIT_REPLY;
        rep.edge         = 0;
        rep.responder_id = (uint32_t) state->fpga_id;
        rep.seq          = req.seq;

        pthread_mutex_lock(&state->lock);
        while (!state->stop_requested && (!state->has_published || state->seq < req.seq)) {
            pthread_cond_wait(&state->cond, &state->lock);
        }
        if (!state->stop_requested && state->has_published && state->seq == req.seq) {
            rep.has_bit   = state->has_bit;
            rep.bit_value = state->bit_value;
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
pull_bit_from_chip(nng_socket data_req, const fpga_options_t *opts, uint64_t seq, uint8_t *have_bit,
    uint8_t *bit_value)
{
    larpixsim_bit_pull_msg_t  req;
    larpixsim_bit_reply_msg_t rep;
    size_t                   rep_sz;
    int                      rv;

    memset(&req, 0, sizeof(req));
    req.type         = LARPIXSIM_MSG_BIT_PULL;
    req.edge         = 0;
    req.requester_id = (uint32_t) opts->id;
    req.seq          = seq;

    rv = nng_send(data_req, &req, sizeof(req), 0);
    if (rv != 0) {
        fprintf(stderr, "fpga_larpix[%d] send(bit_pull) failed: %s\n", opts->id, ERRSTR(rv));
        return -1;
    }

    rep_sz = sizeof(rep);
    rv     = nng_recv(data_req, &rep, &rep_sz, 0);
    if (rv != 0) {
        fprintf(stderr, "fpga_larpix[%d] recv(bit_reply) failed: %s\n", opts->id, ERRSTR(rv));
        return -1;
    }
    if (rep_sz != sizeof(rep) || rep.type != LARPIXSIM_MSG_BIT_REPLY || rep.seq != seq ||
        rep.edge != 0) {
        fprintf(stderr, "fpga_larpix[%d] malformed bit reply\n", opts->id);
        return -1;
    }

    *have_bit  = rep.has_bit ? 1u : 0u;
    *bit_value = rep.bit_value ? 1u : 0u;
    return 0;
}

static std::vector<scheduled_frame_t>
load_schedule(const char *path)
{
    FILE *fp = fopen(path, "r");
    std::vector<scheduled_frame_t> frames;
    std::string                    text;
    char                           buf[4096];
    std::regex frame_re(
        R"(\{[^\}]*"tick_start"\s*:\s*([0-9]+)[^\}]*"packet_word"\s*:\s*"(0x[0-9A-Fa-f]+)"(?:[^\}]*"label"\s*:\s*"([^"]*)")?[^\}]*\})");

    if (fp == NULL) {
        throw std::runtime_error(std::string("failed to open startup_json: ") + path);
    }
    while (fgets(buf, sizeof(buf), fp) != NULL) {
        text += buf;
    }
    fclose(fp);

    for (auto it = std::sregex_iterator(text.begin(), text.end(), frame_re);
         it != std::sregex_iterator(); ++it) {
        scheduled_frame_t frame;
        frame.tick_start  = std::stoull((*it)[1].str());
        frame.packet_word = std::stoull((*it)[2].str(), nullptr, 0);
        frame.label       = (*it)[3].matched ? (*it)[3].str() : std::string();
        frame.bits.reserve(LARPIXSIM_UART_FRAME_BITS);
        frame.bits.push_back(0u);
        for (int i = 0; i < 64; ++i) {
            frame.bits.push_back((frame.packet_word >> i) & 1ULL ? 1u : 0u);
        }
        frame.bits.push_back(1u);
        frames.push_back(frame);
    }

    if (frames.empty()) {
        throw std::runtime_error("startup_json contained no compiled frames");
    }
    return frames;
}

static void
uart_rx_push(uart_rx_state_t *rx, uint8_t bit, fpga_metrics_t *metrics)
{
    if (!rx->active) {
        if (bit == 0u) {
            rx->active = true;
            rx->bits.clear();
            rx->bits.push_back(bit);
        }
        return;
    }

    rx->bits.push_back(bit);
    if (rx->bits.size() == LARPIXSIM_UART_FRAME_BITS) {
        if (rx->bits.front() == 0u && rx->bits.back() == 1u) {
            uint64_t word = 0;
            for (int i = 0; i < 64; ++i) {
                if (rx->bits[1 + i]) {
                    word |= (1ULL << i);
                }
            }
            metrics->decoded_packet_count++;
            printf("fpga_larpix: received packet=0x%016" PRIx64 "\n", word);
        }
        rx->active = false;
        rx->bits.clear();
    }
}

static void
frame_bit_for_tick(const std::vector<scheduled_frame_t>& frames, uint64_t seq, uint8_t *has_bit,
    uint8_t *bit_value)
{
    *has_bit   = 0u;
    *bit_value = 0u;
    for (const auto& frame : frames) {
        if (seq >= frame.tick_start && seq < frame.tick_start + frame.bits.size()) {
            *has_bit   = 1u;
            *bit_value = frame.bits[(size_t) (seq - frame.tick_start)];
            return;
        }
    }
}

int
main(int argc, char **argv)
{
    fpga_options_t               opts;
    fpga_metrics_t               metrics{};
    std::vector<scheduled_frame_t> frames;
    uart_rx_state_t              rx_state;
    nng_socket                   control_rep   = NNG_SOCKET_INITIALIZER;
    nng_socket                   metric_push   = NNG_SOCKET_INITIALIZER;
    nng_socket                   north_in_req  = NNG_SOCKET_INITIALIZER;
    nng_socket                   north_out_rep = NNG_SOCKET_INITIALIZER;
    bit_server_state_t           bit_state;
    bool                         bit_state_inited  = false;
    bool                         bit_thread_started = false;
    pthread_t                    bit_thread;
    int                          rv;
    int                          exit_code = 1;

    if (parse_args(argc, argv, &opts) != 0) {
        usage(argv[0]);
        return 2;
    }

    try {
        frames = load_schedule(opts.startup_json);
    } catch (const std::exception& ex) {
        fprintf(stderr, "fpga_larpix[%d] %s\n", opts.id, ex.what());
        return 1;
    }

    if (nng_init(NULL) != 0) {
        fprintf(stderr, "fpga_larpix[%d] nng_init failed\n", opts.id);
        return 1;
    }

    rv = nng_rep0_open(&control_rep);
    if (rv != 0) goto cleanup;
    rv = nng_listen(control_rep, opts.clock_url, NULL, 0);
    if (rv != 0) goto cleanup;

    rv = nng_push0_open(&metric_push);
    if (rv != 0) goto cleanup;
    rv = nng_dial(metric_push, opts.metric_url, NULL, 0);
    if (rv != 0) goto cleanup;

    rv = nng_rep0_open(&north_out_rep);
    if (rv != 0) goto cleanup;
    rv = nng_listen(north_out_rep, opts.north_out_url, NULL, 0);
    if (rv != 0) goto cleanup;
    if (bit_server_init(&bit_state, north_out_rep, opts.id) != 0) goto cleanup;
    bit_state_inited = true;
    if (pthread_create(&bit_thread, NULL, bit_server_thread_main, &bit_state) != 0) goto cleanup;
    bit_thread_started = true;

    rv = nng_req0_open(&north_in_req);
    if (rv != 0) goto cleanup;
    rv = nng_socket_set_ms(north_in_req, NNG_OPT_SENDTIMEO, opts.data_timeout_ms);
    if (rv != 0) goto cleanup;
    rv = nng_socket_set_ms(north_in_req, NNG_OPT_RECVTIMEO, opts.data_timeout_ms);
    if (rv != 0) goto cleanup;
    rv = nng_socket_set_ms(north_in_req, NNG_OPT_REQ_RESENDTIME, NNG_DURATION_INFINITE);
    if (rv != 0) goto cleanup;
    rv = nng_dial(north_in_req, opts.north_in_url, NULL, NNG_FLAG_NONBLOCK);
    if (rv != 0) goto cleanup;

    for (;;) {
        chipsim_tick_msg_t tick;
        size_t             tick_sz = sizeof(tick);
        uint8_t            tx_has_bit = 0u;
        uint8_t            tx_bit     = 0u;
        uint8_t            rx_has_bit = 0u;
        uint8_t            rx_bit     = 0u;

        rv = nng_recv(control_rep, &tick, &tick_sz, 0);
        if (rv != 0) goto cleanup;
        if (tick_sz != sizeof(tick)) goto cleanup;
        metrics.last_seq = tick.seq;

        if (tick.type == CHIPSIM_MSG_STOP) {
            bit_server_publish(&bit_state, tick.seq, 0u, 0u);
            if (send_done(control_rep, &opts, tick.seq, &metrics) != 0) goto cleanup;
            break;
        }
        if (tick.type != CHIPSIM_MSG_TICK) goto cleanup;

        frame_bit_for_tick(frames, tick.seq, &tx_has_bit, &tx_bit);
        bit_server_publish(&bit_state, tick.seq, tx_has_bit, tx_bit);
        if (tx_has_bit) {
            metrics.tx_count++;
        }

        if (pull_bit_from_chip(north_in_req, &opts, tick.seq, &rx_has_bit, &rx_bit) != 0) goto cleanup;
        if (rx_has_bit) {
            metrics.rx_count++;
            uart_rx_push(&rx_state, rx_bit, &metrics);
        }

        if (send_done(control_rep, &opts, tick.seq, &metrics) != 0) goto cleanup;
    }

    if (send_metric(metric_push, &opts, &metrics) != 0) goto cleanup;
    exit_code = 0;

cleanup:
    if (bit_thread_started) {
        bit_server_request_stop(&bit_state);
    }
    if (nng_socket_id(north_in_req) > 0) nng_socket_close(north_in_req);
    if (nng_socket_id(north_out_rep) > 0) nng_socket_close(north_out_rep);
    if (bit_thread_started) pthread_join(bit_thread, NULL);
    if (bit_state_inited) bit_server_destroy(&bit_state);
    if (nng_socket_id(metric_push) > 0) nng_socket_close(metric_push);
    if (nng_socket_id(control_rep) > 0) nng_socket_close(control_rep);
    nng_fini();
    return exit_code;
}
