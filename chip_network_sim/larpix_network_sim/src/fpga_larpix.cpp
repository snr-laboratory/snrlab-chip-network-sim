/*
 * fpga_larpix.cpp
 *
 * Minimal FPGA/controller runtime for larpix_network_sim. This process sits on
 * the source chip's south edge, injects compiled startup UART frames bit-by-bit
 * into the network, receives UART bits returning from that same edge, and
 * participates in the orchestrator's normal TICK/DONE lock-step.
 */

#include <ctype.h>
#include <errno.h>
#include <inttypes.h>
#include <nng/nng.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <fstream>
#include <sstream>
#include <string>
#include <vector>

#include "chipsim/protocol.h"

#define CHIPSIM_DEFAULT_CLOCK_URL "tcp://127.0.0.1:23000"
#define CHIPSIM_DEFAULT_METRIC_URL "tcp://127.0.0.1:23002"
#define CHIPSIM_DEFAULT_DATA_TIMEOUT_MS 5000
#define LARPIXSIM_MSG_BIT_PULL 101u
#define LARPIXSIM_MSG_BIT_REPLY 102u
#define ERRSTR(x) nng_strerror((nng_err)(x))

enum {
    LARPIX_EDGE_NORTH = 0,
};

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
    uint64_t frame_tx_count;
    uint64_t frame_rx_count;
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
    int             runtime_id;
    int             edge_id;
} bit_server_state_t;

struct scheduled_frame_t {
    uint64_t             tick_start;
    uint64_t             packet_word;
    std::string          label;
    std::vector<uint8_t> uart_bits;
    bool                 wait_for_chip_id_reply = false;
    uint8_t              expected_chip_id_reply = 0;
};

struct readback_request_t {
    uint64_t             packet_word;
    std::string          label;
    std::vector<uint8_t> uart_bits;
};

struct readback_plan_t {
    bool                            enabled = false;
    uint64_t                        start_tick = 0;
    std::vector<readback_request_t> requests;
};

struct uart_decoder_t {
    enum state_t {
        IDLE,
        DATA,
        STOP,
    } state = IDLE;
    uint64_t packet = 0;
    int      bit_idx = 0;
};

static void
usage(const char *prog)
{
    fprintf(stderr,
        "Usage: %s -id <runtime_id> -north_out_url <URI> [options]\n"
        "Options:\n"
        "  -clock_url <URI>          orchestrator control endpoint\n"
        "  -metric_url <URI>         orchestrator metric endpoint\n"
        "  -north_in_url <URI|-1>    source-chip south_out bit service\n"
        "  -north_out_url <URI>      source-chip south_in bit service\n"
        "  -startup_json <path>      compiled startup schedule JSON\n"
        "  -data_timeout_ms <N>      bit-pull timeout in ms (default 5000)\n",
        prog);
}

static int
parse_int(const char *value, int *out)
{
    long v;
    char *end;

    errno = 0;
    v = strtol(value, &end, 10);
    if (errno != 0 || end == value || *end != '\0') {
        return -1;
    }
    if (v < INT32_MIN || v > INT32_MAX) {
        return -1;
    }
    *out = (int)v;
    return 0;
}

static const char *
parse_url_arg(const char *value)
{
    return (strcmp(value, "-1") == 0) ? NULL : value;
}

static int
parse_args(int argc, char **argv, fpga_options_t *opts)
{
    int i;

    memset(opts, 0, sizeof(*opts));
    opts->id = -1;
    opts->clock_url = CHIPSIM_DEFAULT_CLOCK_URL;
    opts->metric_url = CHIPSIM_DEFAULT_METRIC_URL;
    opts->data_timeout_ms = CHIPSIM_DEFAULT_DATA_TIMEOUT_MS;

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
            opts->north_in_url = parse_url_arg(argv[++i]);
        } else if (strcmp(argv[i], "-north_out_url") == 0 && i + 1 < argc) {
            opts->north_out_url = parse_url_arg(argv[++i]);
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

    if (opts->id < 0 || opts->north_out_url == NULL) {
        return -1;
    }
    return 0;
}

static int
send_done(nng_socket control_rep, const fpga_options_t *opts, uint64_t seq, const fpga_metrics_t *metrics)
{
    chipsim_done_msg_t done;
    int rv;

    memset(&done, 0, sizeof(done));
    done.type = CHIPSIM_MSG_DONE;
    done.chip_id = (uint32_t)opts->id;
    done.seq = seq;
    done.tx_count = metrics->tx_count;
    done.rx_count = metrics->rx_count;
    done.local_gen_count = metrics->frame_tx_count;
    done.drop_count = 0;
    done.fifo_occupancy = 0;

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
    int rv;

    memset(&msg, 0, sizeof(msg));
    msg.type = CHIPSIM_MSG_METRIC;
    msg.chip_id = (uint32_t)opts->id;
    msg.seq = metrics->last_seq;
    msg.tx_count = metrics->tx_count;
    msg.rx_count = metrics->rx_count;
    msg.local_gen_count = metrics->frame_tx_count;
    msg.drop_count = 0;
    msg.fifo_occupancy = 0;
    msg.fifo_peak = metrics->frame_rx_count;

    rv = nng_send(metric_push, &msg, sizeof(msg), 0);
    if (rv != 0) {
        fprintf(stderr, "fpga_larpix[%d] failed to send METRIC: %s\n", opts->id, ERRSTR(rv));
        return -1;
    }
    return 0;
}

static int
bit_server_init(bit_server_state_t *state, nng_socket data_rep, int runtime_id, int edge_id)
{
    memset(state, 0, sizeof(*state));
    state->data_rep = data_rep;
    state->runtime_id = runtime_id;
    state->edge_id = edge_id;
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
    state->seq = seq;
    state->has_bit = has_bit ? 1u : 0u;
    state->bit_value = bit_value ? 1u : 0u;
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
    bit_server_state_t *state = (bit_server_state_t *)arg;

    for (;;) {
        larpixsim_bit_pull_msg_t req;
        larpixsim_bit_reply_msg_t rep;
        size_t req_sz = sizeof(req);
        int rv;

        rv = nng_recv(state->data_rep, &req, &req_sz, 0);
        if (rv != 0) {
            break;
        }
        if (req_sz != sizeof(req) || req.type != LARPIXSIM_MSG_BIT_PULL || req.edge != (uint8_t)state->edge_id) {
            continue;
        }

        memset(&rep, 0, sizeof(rep));
        rep.type = LARPIXSIM_MSG_BIT_REPLY;
        rep.edge = (uint8_t)state->edge_id;
        rep.responder_id = (uint32_t)state->runtime_id;
        rep.seq = req.seq;

        pthread_mutex_lock(&state->lock);
        while (!state->stop_requested && (!state->has_published || state->seq < req.seq)) {
            pthread_cond_wait(&state->cond, &state->lock);
        }
        if (!state->stop_requested && state->has_published && state->seq == req.seq) {
            rep.has_bit = state->has_bit;
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
pull_bit_from_chip(nng_socket data_req, const fpga_options_t *opts, uint64_t seq, uint8_t *have_bit, uint8_t *bit_value)
{
    larpixsim_bit_pull_msg_t req;
    larpixsim_bit_reply_msg_t rep;
    size_t rep_sz = sizeof(rep);
    int rv;

    memset(&req, 0, sizeof(req));
    req.type = LARPIXSIM_MSG_BIT_PULL;
    req.edge = (uint8_t)2u;
    req.requester_id = (uint32_t)opts->id;
    req.seq = seq;

    rv = nng_send(data_req, &req, sizeof(req), 0);
    if (rv != 0) {
        fprintf(stderr, "fpga_larpix[%d] send(bit_pull) failed: %s\n", opts->id, ERRSTR(rv));
        return -1;
    }

    rv = nng_recv(data_req, &rep, &rep_sz, 0);
    if (rv != 0) {
        fprintf(stderr, "fpga_larpix[%d] recv(bit_reply) failed: %s\n", opts->id, ERRSTR(rv));
        return -1;
    }
    if (rep_sz != sizeof(rep) || rep.type != LARPIXSIM_MSG_BIT_REPLY || rep.seq != seq || rep.edge != (uint8_t)2u) {
        fprintf(stderr, "fpga_larpix[%d] malformed bit reply\n", opts->id);
        return -1;
    }

    *have_bit = rep.has_bit ? 1u : 0u;
    *bit_value = rep.bit_value ? 1u : 0u;
    return 0;
}

static std::string
read_file_text(const char *path)
{
    std::ifstream in(path);
    std::ostringstream ss;

    if (!in.is_open()) {
        return std::string();
    }
    ss << in.rdbuf();
    return ss.str();
}

static bool
extract_json_string(const std::string &obj, const char *key, std::string *value)
{
    const std::string needle = std::string("\"") + key + "\"";
    size_t pos = obj.find(needle);
    size_t first_quote;
    size_t second_quote;

    if (pos == std::string::npos) {
        return false;
    }
    pos = obj.find(':', pos + needle.size());
    if (pos == std::string::npos) {
        return false;
    }
    first_quote = obj.find('"', pos + 1);
    if (first_quote == std::string::npos) {
        return false;
    }
    second_quote = obj.find('"', first_quote + 1);
    if (second_quote == std::string::npos) {
        return false;
    }
    *value = obj.substr(first_quote + 1, second_quote - first_quote - 1);
    return true;
}

static bool
extract_json_u64(const std::string &obj, const char *key, uint64_t *value)
{
    const std::string needle = std::string("\"") + key + "\"";
    size_t pos = obj.find(needle);
    size_t start;
    size_t end;
    std::string digits;

    if (pos == std::string::npos) {
        return false;
    }
    pos = obj.find(':', pos + needle.size());
    if (pos == std::string::npos) {
        return false;
    }
    start = pos + 1;
    while (start < obj.size() && isspace((unsigned char)obj[start])) {
        start++;
    }
    end = start;
    while (end < obj.size() && isdigit((unsigned char)obj[end])) {
        end++;
    }
    if (end == start) {
        return false;
    }
    digits = obj.substr(start, end - start);
    *value = strtoull(digits.c_str(), NULL, 10);
    return true;
}

static bool
extract_uart_bits(const std::string &obj, std::vector<uint8_t> *bits)
{
    const std::string needle = "\"uart_bits\"";
    size_t pos = obj.find(needle);
    size_t lb;
    size_t rb;
    std::string body;
    size_t i;

    if (pos == std::string::npos) {
        return false;
    }
    lb = obj.find('[', pos + needle.size());
    rb = obj.find(']', lb == std::string::npos ? pos : lb + 1);
    if (lb == std::string::npos || rb == std::string::npos || rb <= lb) {
        return false;
    }
    body = obj.substr(lb + 1, rb - lb - 1);
    bits->clear();
    for (i = 0; i < body.size(); ) {
        while (i < body.size() && (isspace((unsigned char)body[i]) || body[i] == ',')) {
            i++;
        }
        if (i >= body.size()) {
            break;
        }
        if (body[i] != '0' && body[i] != '1') {
            return false;
        }
        bits->push_back((uint8_t)(body[i] - '0'));
        i++;
    }
    return true;
}

static bool
extract_json_object(const std::string &obj, const char *key, std::string *value)
{
    const std::string needle = std::string("\"") + key + "\"";
    size_t pos = obj.find(needle);
    size_t start;
    size_t end;
    int depth;

    if (pos == std::string::npos) {
        return false;
    }
    pos = obj.find(':', pos + needle.size());
    if (pos == std::string::npos) {
        return false;
    }
    start = obj.find('{', pos + 1);
    if (start == std::string::npos) {
        return false;
    }
    end = start;
    depth = 0;
    while (end < obj.size()) {
        if (obj[end] == '{') {
            depth++;
        } else if (obj[end] == '}') {
            depth--;
            if (depth == 0) {
                end++;
                break;
            }
        }
        end++;
    }
    if (depth != 0 || end <= start) {
        return false;
    }
    *value = obj.substr(start, end - start);
    return true;
}

static bool
extract_json_array(const std::string &obj, const char *key, std::string *value)
{
    const std::string needle = std::string("\"") + key + "\"";
    size_t pos = obj.find(needle);
    size_t start;
    size_t end;
    int depth;

    if (pos == std::string::npos) {
        return false;
    }
    pos = obj.find(':', pos + needle.size());
    if (pos == std::string::npos) {
        return false;
    }
    start = obj.find('[', pos + 1);
    if (start == std::string::npos) {
        return false;
    }
    end = start;
    depth = 0;
    while (end < obj.size()) {
        if (obj[end] == '[') {
            depth++;
        } else if (obj[end] == ']') {
            depth--;
            if (depth == 0) {
                end++;
                break;
            }
        }
        end++;
    }
    if (depth != 0 || end <= start) {
        return false;
    }
    *value = obj.substr(start, end - start);
    return true;
}

static int
parse_readback_plan(const std::string &text, readback_plan_t *plan)
{
    std::string phase_obj;
    std::string requests_array;
    size_t pos;

    if (!extract_json_object(text, "readback_phase", &phase_obj)) {
        return 0;
    }
    plan->enabled = true;
    if (!extract_json_u64(phase_obj, "start_tick", &plan->start_tick)) {
        fprintf(stderr, "fpga_larpix: malformed readback_phase.start_tick\n");
        return -1;
    }
    if (!extract_json_array(phase_obj, "requests", &requests_array)) {
        fprintf(stderr, "fpga_larpix: malformed readback_phase.requests\n");
        return -1;
    }

    pos = 0;
    while (pos < requests_array.size()) {
        size_t obj_start = requests_array.find('{', pos);
        size_t obj_end;
        int depth;
        readback_request_t req;
        std::string obj;
        std::string packet_word_text;

        if (obj_start == std::string::npos) {
            break;
        }
        obj_end = obj_start;
        depth = 0;
        while (obj_end < requests_array.size()) {
            if (requests_array[obj_end] == '{') {
                depth++;
            } else if (requests_array[obj_end] == '}') {
                depth--;
                if (depth == 0) {
                    obj_end++;
                    break;
                }
            }
            obj_end++;
        }
        if (depth != 0 || obj_end <= obj_start) {
            fprintf(stderr, "fpga_larpix: malformed readback request object\n");
            return -1;
        }
        obj = requests_array.substr(obj_start, obj_end - obj_start);
        if (!extract_json_string(obj, "packet_word", &packet_word_text) || !extract_uart_bits(obj, &req.uart_bits)) {
            fprintf(stderr, "fpga_larpix: malformed readback request entry\n");
            return -1;
        }
        if (!extract_json_string(obj, "label", &req.label)) {
            req.label = std::string();
        }
        req.packet_word = strtoull(packet_word_text.c_str(), NULL, 0);
        if (req.uart_bits.empty()) {
            fprintf(stderr, "fpga_larpix: empty readback uart_bits entry\n");
            return -1;
        }
        plan->requests.push_back(req);
        pos = obj_end;
    }

    return 0;
}

static int
load_schedule(const char *path, std::vector<scheduled_frame_t> *frames, readback_plan_t *readback_plan)
{
    std::string text;
    size_t frames_key;
    size_t lb;
    size_t rb;
    size_t pos;

    frames->clear();
    *readback_plan = readback_plan_t();
    if (path == NULL) {
        return 0;
    }

    text = read_file_text(path);
    if (text.empty()) {
        fprintf(stderr, "fpga_larpix: failed to read startup_json %s\n", path);
        return -1;
    }

    frames_key = text.find("\"frames\"");
    if (frames_key == std::string::npos) {
        fprintf(stderr, "fpga_larpix: startup_json missing frames array\n");
        return -1;
    }
    lb = text.find('[', frames_key);
    if (lb == std::string::npos) {
        return -1;
    }
    {
        int bracket_depth = 0;
        rb = lb;
        while (rb < text.size()) {
            if (text[rb] == '[') {
                bracket_depth++;
            } else if (text[rb] == ']') {
                bracket_depth--;
                if (bracket_depth == 0) {
                    break;
                }
            }
            rb++;
        }
    }
    if (rb == std::string::npos || rb >= text.size()) {
        return -1;
    }

    pos = lb + 1;
    while (pos < rb) {
        size_t obj_start = text.find('{', pos);
        size_t obj_end;
        int depth;
        scheduled_frame_t frame;
        std::string obj;
        std::string packet_word_text;

        if (obj_start == std::string::npos || obj_start >= rb) {
            break;
        }
        obj_end = obj_start;
        depth = 0;
        while (obj_end < rb) {
            if (text[obj_end] == '{') {
                depth++;
            } else if (text[obj_end] == '}') {
                depth--;
                if (depth == 0) {
                    obj_end++;
                    break;
                }
            }
            obj_end++;
        }
        if (obj_end <= obj_start || depth != 0) {
            fprintf(stderr, "fpga_larpix: malformed frame object in startup_json\n");
            return -1;
        }
        obj = text.substr(obj_start, obj_end - obj_start);
        if (!extract_json_u64(obj, "tick_start", &frame.tick_start) ||
            !extract_json_string(obj, "packet_word", &packet_word_text) ||
            !extract_uart_bits(obj, &frame.uart_bits)) {
            fprintf(stderr, "fpga_larpix: malformed frame entry in startup_json\n");
            return -1;
        }
        if (!extract_json_string(obj, "label", &frame.label)) {
            frame.label = std::string();
        }
        {
            uint64_t wait_chip = 0;
            if (extract_json_u64(obj, "wait_for_chip_id_reply", &wait_chip)) {
                if (wait_chip > 255u) {
                    fprintf(stderr, "fpga_larpix: invalid wait_for_chip_id_reply value\n");
                    return -1;
                }
                frame.wait_for_chip_id_reply = true;
                frame.expected_chip_id_reply = (uint8_t)wait_chip;
            }
        }
        frame.packet_word = strtoull(packet_word_text.c_str(), NULL, 0);
        if (frame.uart_bits.empty()) {
            fprintf(stderr, "fpga_larpix: empty uart_bits frame in startup_json\n");
            return -1;
        }
        frames->push_back(frame);
        pos = obj_end;
    }

    if (parse_readback_plan(text, readback_plan) != 0) {
        return -1;
    }

    return 0;
}

static int
build_bit_schedule(const std::vector<scheduled_frame_t> &frames, std::vector<uint8_t> *bits, uint64_t *base_tick)
{
    uint64_t max_tick = 0;
    size_t i;

    bits->clear();
    *base_tick = 0;
    if (frames.empty()) {
        return 0;
    }

    *base_tick = frames[0].tick_start;
    for (i = 0; i < frames.size(); i++) {
        uint64_t end_tick = frames[i].tick_start + (uint64_t)frames[i].uart_bits.size();
        if (frames[i].tick_start < *base_tick) {
            *base_tick = frames[i].tick_start;
        }
        if (end_tick > max_tick) {
            max_tick = end_tick;
        }
    }

    bits->assign((size_t)(max_tick - *base_tick), 2u);
    for (i = 0; i < frames.size(); i++) {
        size_t j;
        for (j = 0; j < frames[i].uart_bits.size(); j++) {
            size_t idx = (size_t)((frames[i].tick_start - *base_tick) + j);
            if ((*bits)[idx] != 2u) {
                fprintf(stderr, "fpga_larpix: overlapping startup frames at tick=%" PRIu64 "\n",
                    *base_tick + (uint64_t)idx);
                return -1;
            }
            (*bits)[idx] = frames[i].uart_bits[j] ? 1u : 0u;
        }
    }
    return 0;
}

static void
uart_decoder_reset(uart_decoder_t *decoder)
{
    decoder->state = uart_decoder_t::IDLE;
    decoder->packet = 0;
    decoder->bit_idx = 0;
}

static bool
uart_decoder_consume(uart_decoder_t *decoder, uint8_t have_bit, uint8_t bit_value, uint64_t *packet_out)
{
    if (!have_bit) {
        return false;
    }

    switch (decoder->state) {
    case uart_decoder_t::IDLE:
        if ((bit_value & 1u) == 0u) {
            decoder->state = uart_decoder_t::DATA;
            decoder->packet = 0;
            decoder->bit_idx = 0;
        }
        break;
    case uart_decoder_t::DATA:
        decoder->packet |= ((uint64_t)(bit_value & 1u) << decoder->bit_idx);
        decoder->bit_idx++;
        if (decoder->bit_idx >= 64) {
            decoder->state = uart_decoder_t::STOP;
        }
        break;
    case uart_decoder_t::STOP:
        *packet_out = decoder->packet;
        uart_decoder_reset(decoder);
        return (bit_value & 1u) == 1u;
    }

    return false;
}

static bool
packet_has_odd_parity(uint64_t word)
{
    unsigned ones = 0u;
    while (word != 0u) {
        ones += (unsigned)(word & 1u);
        word >>= 1;
    }
    return (ones & 1u) == 1u;
}

static bool
is_matching_chip_id_reply(uint64_t word, uint8_t expected_chip_id)
{
    uint64_t payload = word & ((UINT64_C(1) << 63) - 1u);
    uint8_t packet_type = (uint8_t)(payload & 0x3u);
    uint8_t chip_id = (uint8_t)((payload >> 2) & 0xFFu);
    uint8_t register_addr = (uint8_t)((payload >> 10) & 0xFFu);
    uint8_t register_data = (uint8_t)((payload >> 18) & 0xFFu);

    return packet_has_odd_parity(word) &&
           packet_type == 0x3u &&
           chip_id == expected_chip_id &&
           register_addr == 122u &&
           register_data == expected_chip_id;
}

int
main(int argc, char **argv)
{
    fpga_options_t opts;
    fpga_metrics_t metrics;
    nng_socket control_rep = NNG_SOCKET_INITIALIZER;
    nng_socket metric_push = NNG_SOCKET_INITIALIZER;
    nng_socket north_in_req = NNG_SOCKET_INITIALIZER;
    nng_socket north_out_rep = NNG_SOCKET_INITIALIZER;
    bit_server_state_t north_state;
    pthread_t north_thread;
    bool north_state_inited = false;
    bool north_thread_started = false;
    std::vector<scheduled_frame_t> frames;
    readback_plan_t readback_plan;
    size_t startup_frame_index = 0;
    size_t startup_bit_index = 0;
    bool startup_tx_active = false;
    bool startup_waiting_for_reply = false;
    size_t readback_request_index = 0;
    size_t readback_bit_index = 0;
    bool readback_tx_active = false;
    bool readback_waiting_for_reply = false;
    uart_decoder_t decoder;
    int rv;
    int exit_code = 1;
    nng_err init_err;

    memset(&metrics, 0, sizeof(metrics));
    uart_decoder_reset(&decoder);

    if (parse_args(argc, argv, &opts) != 0) {
        usage(argv[0]);
        return 2;
    }

    if (load_schedule(opts.startup_json, &frames, &readback_plan) != 0) {
        return 1;
    }

    init_err = nng_init(NULL);
    if (init_err != 0) {
        fprintf(stderr, "fpga_larpix nng_init failed: %s\n", nng_strerror(init_err));
        return 1;
    }

    rv = nng_rep0_open(&control_rep);
    if (rv != 0) {
        fprintf(stderr, "fpga_larpix[%d] open(control) failed: %s\n", opts.id, ERRSTR(rv));
        goto cleanup;
    }
    rv = nng_listen(control_rep, opts.clock_url, NULL, 0);
    if (rv != 0) {
        fprintf(stderr, "fpga_larpix[%d] listen(control) failed at %s: %s\n", opts.id, opts.clock_url, ERRSTR(rv));
        goto cleanup;
    }

    rv = nng_push0_open(&metric_push);
    if (rv != 0) {
        fprintf(stderr, "fpga_larpix[%d] open(metric) failed: %s\n", opts.id, ERRSTR(rv));
        goto cleanup;
    }
    rv = nng_dial(metric_push, opts.metric_url, NULL, 0);
    if (rv != 0) {
        fprintf(stderr, "fpga_larpix[%d] dial(metric) failed: %s\n", opts.id, ERRSTR(rv));
        goto cleanup;
    }

    rv = nng_rep0_open(&north_out_rep);
    if (rv != 0) {
        fprintf(stderr, "fpga_larpix[%d] open(north_out_rep) failed: %s\n", opts.id, ERRSTR(rv));
        goto cleanup;
    }
    rv = nng_listen(north_out_rep, opts.north_out_url, NULL, 0);
    if (rv != 0) {
        fprintf(stderr, "fpga_larpix[%d] listen(north_out_rep) failed at %s: %s\n", opts.id, opts.north_out_url, ERRSTR(rv));
        goto cleanup;
    }
    if (bit_server_init(&north_state, north_out_rep, opts.id, LARPIX_EDGE_NORTH) != 0) {
        fprintf(stderr, "fpga_larpix[%d] bit server init failed\n", opts.id);
        goto cleanup;
    }
    north_state_inited = true;
    if (pthread_create(&north_thread, NULL, bit_server_thread_main, &north_state) != 0) {
        fprintf(stderr, "fpga_larpix[%d] bit server thread create failed\n", opts.id);
        goto cleanup;
    }
    north_thread_started = true;

    if (opts.north_in_url != NULL) {
        rv = nng_req0_open(&north_in_req);
        if (rv != 0) {
            fprintf(stderr, "fpga_larpix[%d] open(north_in_req) failed: %s\n", opts.id, ERRSTR(rv));
            goto cleanup;
        }
        rv = nng_socket_set_ms(north_in_req, NNG_OPT_SENDTIMEO, opts.data_timeout_ms);
        if (rv != 0) {
            goto cleanup;
        }
        rv = nng_socket_set_ms(north_in_req, NNG_OPT_RECVTIMEO, opts.data_timeout_ms);
        if (rv != 0) {
            goto cleanup;
        }
        rv = nng_socket_set_ms(north_in_req, NNG_OPT_REQ_RESENDTIME, NNG_DURATION_INFINITE);
        if (rv != 0) {
            goto cleanup;
        }
        rv = nng_dial(north_in_req, opts.north_in_url, NULL, NNG_FLAG_NONBLOCK);
        if (rv != 0) {
            fprintf(stderr, "fpga_larpix[%d] dial(north_in_req) failed at %s: %s\n", opts.id, opts.north_in_url, ERRSTR(rv));
            goto cleanup;
        }
    }

    for (;;) {
        chipsim_tick_msg_t tick;
        size_t tick_sz = sizeof(tick);
        uint8_t tx_have_bit = 0u;
        uint8_t tx_bit = 0u;

        rv = nng_recv(control_rep, &tick, &tick_sz, 0);
        if (rv != 0) {
            fprintf(stderr, "fpga_larpix[%d] recv(control) failed: %s\n", opts.id, ERRSTR(rv));
            goto cleanup;
        }
        if (tick_sz != sizeof(tick)) {
            fprintf(stderr, "fpga_larpix[%d] malformed control message\n", opts.id);
            goto cleanup;
        }
        metrics.last_seq = tick.seq;

        if (tick.type == CHIPSIM_MSG_STOP) {
            bit_server_publish(&north_state, tick.seq, 0u, 0u);
            if (send_done(control_rep, &opts, tick.seq, &metrics) != 0) {
                goto cleanup;
            }
            break;
        }
        if (tick.type != CHIPSIM_MSG_TICK) {
            fprintf(stderr, "fpga_larpix[%d] unknown control type=%u\n", opts.id, (unsigned)tick.type);
            goto cleanup;
        }

        if (!startup_tx_active && !startup_waiting_for_reply && startup_frame_index < frames.size() &&
            tick.seq >= frames[startup_frame_index].tick_start) {
            startup_tx_active = true;
            startup_bit_index = 0;
        }

        if (startup_tx_active) {
            const scheduled_frame_t &frame = frames[startup_frame_index];
            if (startup_bit_index < frame.uart_bits.size()) {
                tx_have_bit = 1u;
                tx_bit = frame.uart_bits[startup_bit_index] ? 1u : 0u;
                startup_bit_index++;
                if (startup_bit_index == frame.uart_bits.size()) {
                    startup_tx_active = false;
                    metrics.frame_tx_count++;
                    printf("fpga_larpix[%d] transmitted frame at seq=%" PRIu64 " : 0x%016" PRIx64,
                        opts.id, tick.seq, frame.packet_word);
                    if (!frame.label.empty()) {
                        printf(" label=%s", frame.label.c_str());
                    }
                    printf("\n");
                    fflush(stdout);
                    if (frame.wait_for_chip_id_reply) {
                        startup_waiting_for_reply = true;
                    } else {
                        startup_frame_index++;
                    }
                }
            }
        }

        if (!tx_have_bit && readback_plan.enabled && !startup_tx_active && !startup_waiting_for_reply &&
            startup_frame_index >= frames.size() && tick.seq >= readback_plan.start_tick &&
            readback_request_index < readback_plan.requests.size()) {
            if (!readback_tx_active && !readback_waiting_for_reply) {
                readback_tx_active = true;
                readback_bit_index = 0;
            }
            if (readback_tx_active) {
                const readback_request_t &req = readback_plan.requests[readback_request_index];
                if (readback_bit_index < req.uart_bits.size()) {
                    tx_have_bit = 1u;
                    tx_bit = req.uart_bits[readback_bit_index] ? 1u : 0u;
                    readback_bit_index++;
                    if (readback_bit_index == req.uart_bits.size()) {
                        readback_tx_active = false;
                        readback_waiting_for_reply = true;
                        metrics.frame_tx_count++;
                        printf("fpga_larpix[%d] transmitted frame at seq=%" PRIu64 ": 0x%016" PRIx64,
                            opts.id, tick.seq, req.packet_word);
                        if (!req.label.empty()) {
                            printf(" label=%s", req.label.c_str());
                        }
                        printf("\n");
                        fflush(stdout);
                    }
                }
            }
        }

        bit_server_publish(&north_state, tick.seq, tx_have_bit, tx_bit);
        if (tx_have_bit) {
            metrics.tx_count++;
        }

        if (nng_socket_id(north_in_req) > 0) {
            uint8_t rx_have_bit = 0u;
            uint8_t rx_bit = 0u;
            uint64_t packet = 0;
            if (pull_bit_from_chip(north_in_req, &opts, tick.seq, &rx_have_bit, &rx_bit) != 0) {
                goto cleanup;
            }
            if (rx_have_bit) {
                metrics.rx_count++;
                if (uart_decoder_consume(&decoder, rx_have_bit, rx_bit, &packet)) {
                    metrics.frame_rx_count++;
                    printf("fpga_larpix[%d] received packet at seq=%" PRIu64 ": 0x%016" PRIx64 "\n",
                        opts.id, tick.seq, packet);
                    fflush(stdout);
                    if (startup_waiting_for_reply && startup_frame_index < frames.size() &&
                        is_matching_chip_id_reply(packet, frames[startup_frame_index].expected_chip_id_reply)) {
                        startup_waiting_for_reply = false;
                        startup_frame_index++;
                    }
                    if (readback_waiting_for_reply && readback_request_index < readback_plan.requests.size() &&
                        is_matching_chip_id_reply(packet, (uint8_t)readback_request_index)) {
                        readback_waiting_for_reply = false;
                        readback_request_index++;
                    }
                }
            }
        }

        if (send_done(control_rep, &opts, tick.seq, &metrics) != 0) {
            goto cleanup;
        }
    }

    if (send_metric(metric_push, &opts, &metrics) != 0) {
        goto cleanup;
    }

    exit_code = 0;

cleanup:
    if (north_thread_started) {
        bit_server_request_stop(&north_state);
    }
    if (nng_socket_id(north_in_req) > 0) {
        nng_socket_close(north_in_req);
    }
    if (nng_socket_id(north_out_rep) > 0) {
        nng_socket_close(north_out_rep);
    }
    if (north_thread_started) {
        pthread_join(north_thread, NULL);
    }
    if (north_state_inited) {
        bit_server_destroy(&north_state);
    }
    if (nng_socket_id(metric_push) > 0) {
        nng_socket_close(metric_push);
    }
    if (nng_socket_id(control_rep) > 0) {
        nng_socket_close(control_rep);
    }
    nng_fini();
    return exit_code;
}
