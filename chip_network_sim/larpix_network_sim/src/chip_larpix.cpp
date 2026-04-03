#include <errno.h>
#include <inttypes.h>
#include <limits.h>
#include <nng/nng.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <algorithm>
#include <cctype>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

#include "chipsim/protocol.h"
#include "chipsim/trace.h"
#include "larpixsim/backend.h"

#define CHIPSIM_DEFAULT_CLOCK_URL "tcp://127.0.0.1:23000"
#define CHIPSIM_DEFAULT_METRIC_URL "tcp://127.0.0.1:23002"
#define CHIPSIM_DEFAULT_DATA_TIMEOUT_MS 5000
#define LARPIXSIM_MSG_BIT_PULL 101u
#define LARPIXSIM_MSG_BIT_REPLY 102u
#define ERRSTR(x) nng_strerror((nng_err)(x))

typedef enum {
    LARPIX_EDGE_NORTH = 0,
    LARPIX_EDGE_EAST  = 1,
    LARPIX_EDGE_SOUTH = 2,
    LARPIX_EDGE_WEST  = 3,
} larpix_edge_t;

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
    uint32_t    seed;
    int         data_timeout_ms;
    const char *clock_url;
    const char *metric_url;
    const char *trace_file;
    const char *backend_name;
    const char *stimulus_json;
    const char *in_url[LARPIXSIM_EDGE_COUNT];
    const char *out_url[LARPIXSIM_EDGE_COUNT];
} chip_options_t;

typedef struct {
    uint64_t tx_count;
    uint64_t rx_count;
    uint64_t local_event_count;
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
    uint8_t         has_bit;
    uint8_t         bit_value;
    nng_socket      data_rep;
    int             chip_id;
    int             edge_id;
} bit_server_state_t;

typedef struct {
    uint64_t tick;
    int      channel;
    double   charge;
} stimulus_event_t;

static int
opposite_edge(int edge)
{
    switch (edge) {
    case LARPIX_EDGE_NORTH:
        return LARPIX_EDGE_SOUTH;
    case LARPIX_EDGE_EAST:
        return LARPIX_EDGE_WEST;
    case LARPIX_EDGE_SOUTH:
        return LARPIX_EDGE_NORTH;
    case LARPIX_EDGE_WEST:
        return LARPIX_EDGE_EAST;
    default:
        return edge;
    }
}

static const char *
edge_name(int edge)
{
    switch (edge) {
    case LARPIX_EDGE_NORTH:
        return "north";
    case LARPIX_EDGE_EAST:
        return "east";
    case LARPIX_EDGE_SOUTH:
        return "south";
    case LARPIX_EDGE_WEST:
        return "west";
    default:
        return "unknown";
    }
}

static void
usage(const char *prog)
{
    fprintf(stderr,
        "Usage: %s -id <runtime_id> [options]\n"
        "Options:\n"
        "  -backend <name>            backend mode (default cosim)\n"
        "  -clock_url <URI>           orchestrator control endpoint\n"
        "  -metric_url <URI>          orchestrator metric endpoint\n"
        "  -north_in_url <URI|-1>     north input bit service\n"
        "  -east_in_url <URI|-1>      east input bit service\n"
        "  -south_in_url <URI|-1>     south input bit service\n"
        "  -west_in_url <URI|-1>      west input bit service\n"
        "  -north_out_url <URI|-1>    north output bit service\n"
        "  -east_out_url <URI|-1>     east output bit service\n"
        "  -south_out_url <URI|-1>    south output bit service\n"
        "  -west_out_url <URI|-1>     west output bit service\n"
        "  -stimulus_json <path>      charge stimulus configuration\n"
        "  -data_timeout_ms <N>       edge pull timeout in ms (default 5000)\n"
        "  -seed <N>                  RNG seed / backend seed (default 1)\n"
        "  -trace_file <path>         optional binary trace output path\n",
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
    if (v < INT_MIN || v > INT_MAX) {
        return -1;
    }
    *out = (int)v;
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
    *out = (uint32_t)v;
    return 0;
}

static const char *
parse_edge_url_arg(const char *value)
{
    return (strcmp(value, "-1") == 0) ? NULL : value;
}

static int
parse_args(int argc, char **argv, chip_options_t *opts)
{
    int i;

    memset(opts, 0, sizeof(*opts));
    opts->id              = -1;
    opts->seed            = 1u;
    opts->data_timeout_ms = CHIPSIM_DEFAULT_DATA_TIMEOUT_MS;
    opts->clock_url       = CHIPSIM_DEFAULT_CLOCK_URL;
    opts->metric_url      = CHIPSIM_DEFAULT_METRIC_URL;
    opts->backend_name    = "cosim";

    for (i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-id") == 0 && i + 1 < argc) {
            if (parse_int(argv[++i], &opts->id) != 0) {
                return -1;
            }
        } else if (strcmp(argv[i], "-backend") == 0 && i + 1 < argc) {
            opts->backend_name = argv[++i];
        } else if (strcmp(argv[i], "-clock_url") == 0 && i + 1 < argc) {
            opts->clock_url = argv[++i];
        } else if (strcmp(argv[i], "-metric_url") == 0 && i + 1 < argc) {
            opts->metric_url = argv[++i];
        } else if (strcmp(argv[i], "-north_in_url") == 0 && i + 1 < argc) {
            opts->in_url[LARPIX_EDGE_NORTH] = parse_edge_url_arg(argv[++i]);
        } else if (strcmp(argv[i], "-east_in_url") == 0 && i + 1 < argc) {
            opts->in_url[LARPIX_EDGE_EAST] = parse_edge_url_arg(argv[++i]);
        } else if (strcmp(argv[i], "-south_in_url") == 0 && i + 1 < argc) {
            opts->in_url[LARPIX_EDGE_SOUTH] = parse_edge_url_arg(argv[++i]);
        } else if (strcmp(argv[i], "-west_in_url") == 0 && i + 1 < argc) {
            opts->in_url[LARPIX_EDGE_WEST] = parse_edge_url_arg(argv[++i]);
        } else if (strcmp(argv[i], "-north_out_url") == 0 && i + 1 < argc) {
            opts->out_url[LARPIX_EDGE_NORTH] = parse_edge_url_arg(argv[++i]);
        } else if (strcmp(argv[i], "-east_out_url") == 0 && i + 1 < argc) {
            opts->out_url[LARPIX_EDGE_EAST] = parse_edge_url_arg(argv[++i]);
        } else if (strcmp(argv[i], "-south_out_url") == 0 && i + 1 < argc) {
            opts->out_url[LARPIX_EDGE_SOUTH] = parse_edge_url_arg(argv[++i]);
        } else if (strcmp(argv[i], "-west_out_url") == 0 && i + 1 < argc) {
            opts->out_url[LARPIX_EDGE_WEST] = parse_edge_url_arg(argv[++i]);
        } else if (strcmp(argv[i], "-stimulus_json") == 0 && i + 1 < argc) {
            opts->stimulus_json = argv[++i];
        } else if (strcmp(argv[i], "-data_timeout_ms") == 0 && i + 1 < argc) {
            if (parse_int(argv[++i], &opts->data_timeout_ms) != 0 || opts->data_timeout_ms <= 0) {
                return -1;
            }
        } else if (strcmp(argv[i], "-seed") == 0 && i + 1 < argc) {
            if (parse_u32(argv[++i], &opts->seed) != 0) {
                return -1;
            }
        } else if (strcmp(argv[i], "-trace_file") == 0 && i + 1 < argc) {
            opts->trace_file = argv[++i];
        } else {
            return -1;
        }
    }

    return (opts->id >= 0) ? 0 : -1;
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

static std::string
strip_json_line_comments(const std::string &text)
{
    std::ostringstream out;
    std::istringstream in(text);
    std::string line;

    while (std::getline(in, line)) {
        std::size_t pos = 0;
        while (pos < line.size() && std::isspace((unsigned char)line[pos])) {
            pos++;
        }
        if (pos + 1 < line.size() && line[pos] == '/' && line[pos + 1] == '/') {
            continue;
        }
        out << line << '\n';
    }
    return out.str();
}

static bool
extract_json_u64(const std::string &obj, const char *key, uint64_t *value)
{
    const std::string needle = std::string("\"") + key + "\"";
    std::size_t pos = obj.find(needle);
    std::size_t start;
    std::size_t end;
    std::string digits;

    if (pos == std::string::npos) {
        return false;
    }
    pos = obj.find(':', pos + needle.size());
    if (pos == std::string::npos) {
        return false;
    }
    start = pos + 1;
    while (start < obj.size() && std::isspace((unsigned char)obj[start])) {
        start++;
    }
    end = start;
    while (end < obj.size() && std::isdigit((unsigned char)obj[end])) {
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
extract_json_int_optional(const std::string &obj, const char *key, int *value)
{
    uint64_t tmp = 0;
    if (!extract_json_u64(obj, key, &tmp)) {
        return false;
    }
    *value = (int)tmp;
    return true;
}

static bool
extract_json_double(const std::string &obj, const char *key, double *value)
{
    const std::string needle = std::string("\"") + key + "\"";
    std::size_t pos = obj.find(needle);
    std::size_t start;
    std::size_t end;
    std::string token;

    if (pos == std::string::npos) {
        return false;
    }
    pos = obj.find(':', pos + needle.size());
    if (pos == std::string::npos) {
        return false;
    }
    start = pos + 1;
    while (start < obj.size() && std::isspace((unsigned char)obj[start])) {
        start++;
    }
    end = start;
    while (end < obj.size()) {
        char c = obj[end];
        if (!(std::isdigit((unsigned char)c) || c == '+' || c == '-' || c == '.' || c == 'e' || c == 'E')) {
            break;
        }
        end++;
    }
    if (end == start) {
        return false;
    }
    token = obj.substr(start, end - start);
    *value = strtod(token.c_str(), NULL);
    return true;
}

static int
load_stimulus_events(const chip_options_t *opts, std::vector<stimulus_event_t> *events)
{
    std::string text;
    std::size_t charges_key;
    std::size_t lb;
    std::size_t rb;
    std::size_t pos;

    events->clear();
    if (opts->stimulus_json == NULL) {
        return 0;
    }

    text = strip_json_line_comments(read_file_text(opts->stimulus_json));
    if (text.empty()) {
        fprintf(stderr, "chip_larpix[%d] failed to read stimulus_json %s\n", opts->id, opts->stimulus_json);
        return -1;
    }

    charges_key = text.find("\"charges\"");
    if (charges_key == std::string::npos) {
        fprintf(stderr, "chip_larpix[%d] stimulus_json missing charges array\n", opts->id);
        return -1;
    }
    lb = text.find('[', charges_key);
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
        std::size_t obj_start = text.find('{', pos);
        std::size_t obj_end;
        int depth;
        std::string obj;
        stimulus_event_t ev{};
        int runtime_id = -1;

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
            fprintf(stderr, "chip_larpix[%d] malformed stimulus object\n", opts->id);
            return -1;
        }
        obj = text.substr(obj_start, obj_end - obj_start);
        if (!extract_json_u64(obj, "tick", &ev.tick) ||
            !extract_json_int_optional(obj, "channel", &ev.channel) ||
            !extract_json_double(obj, "charge", &ev.charge)) {
            fprintf(stderr, "chip_larpix[%d] malformed stimulus entry\n", opts->id);
            return -1;
        }
        if (ev.channel < 0 || ev.channel >= LARPIXSIM_CHANNEL_COUNT) {
            fprintf(stderr, "chip_larpix[%d] stimulus channel out of range: %d\n", opts->id, ev.channel);
            return -1;
        }
        if (extract_json_int_optional(obj, "runtime_id", &runtime_id) && runtime_id != opts->id) {
            pos = obj_end;
            continue;
        }
        events->push_back(ev);
        pos = obj_end;
    }

    std::sort(events->begin(), events->end(), [](const stimulus_event_t &a, const stimulus_event_t &b) {
        if (a.tick != b.tick) return a.tick < b.tick;
        return a.channel < b.channel;
    });
    return 0;
}

static int
send_done(nng_socket control_rep, const chip_options_t *opts, uint64_t seq, const chip_metrics_t *metrics)
{
    chipsim_done_msg_t done;
    int                rv;

    memset(&done, 0, sizeof(done));
    done.type            = CHIPSIM_MSG_DONE;
    done.chip_id         = (uint32_t)opts->id;
    done.seq             = seq;
    done.tx_count        = metrics->tx_count;
    done.rx_count        = metrics->rx_count;
    done.local_gen_count = metrics->local_event_count;
    done.drop_count      = metrics->drop_count;
    done.fifo_occupancy  = 0;

    rv = nng_send(control_rep, &done, sizeof(done), 0);
    if (rv != 0) {
        fprintf(stderr, "chip_larpix[%d] failed to send DONE: %s\n", opts->id, ERRSTR(rv));
        return -1;
    }
    return 0;
}

static int
send_metric(nng_socket metric_push, const chip_options_t *opts, const chip_metrics_t *metrics)
{
    chipsim_metric_msg_t msg;
    int                  rv;

    memset(&msg, 0, sizeof(msg));
    msg.type            = CHIPSIM_MSG_METRIC;
    msg.chip_id         = (uint32_t)opts->id;
    msg.seq             = metrics->last_seq;
    msg.tx_count        = metrics->tx_count;
    msg.rx_count        = metrics->rx_count;
    msg.local_gen_count = metrics->local_event_count;
    msg.drop_count      = metrics->drop_count;
    msg.fifo_occupancy  = 0;
    msg.fifo_peak       = metrics->fifo_peak;

    rv = nng_send(metric_push, &msg, sizeof(msg), 0);
    if (rv != 0) {
        fprintf(stderr, "chip_larpix[%d] failed to send METRIC: %s\n", opts->id, ERRSTR(rv));
        return -1;
    }
    return 0;
}

static int
bit_server_init(bit_server_state_t *state, nng_socket data_rep, int chip_id, int edge_id)
{
    memset(state, 0, sizeof(*state));
    state->data_rep = data_rep;
    state->chip_id  = chip_id;
    state->edge_id  = edge_id;
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
    bit_server_state_t *state = (bit_server_state_t *)arg;

    for (;;) {
        larpixsim_bit_pull_msg_t req;
        larpixsim_bit_reply_msg_t rep;
        size_t                   req_sz = sizeof(req);
        int                      rv;

        rv = nng_recv(state->data_rep, &req, &req_sz, 0);
        if (rv != 0) {
            break;
        }
        if (req_sz != sizeof(req) || req.type != LARPIXSIM_MSG_BIT_PULL) {
            continue;
        }
        if (req.edge != (uint8_t)state->edge_id) {
            continue;
        }

        memset(&rep, 0, sizeof(rep));
        rep.type         = LARPIXSIM_MSG_BIT_REPLY;
        rep.edge         = (uint8_t)state->edge_id;
        rep.responder_id = (uint32_t)state->chip_id;
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
pull_bit_from_edge(nng_socket data_req, const chip_options_t *opts, int edge,
    uint64_t seq, uint8_t *have_bit, uint8_t *bit_value)
{
    larpixsim_bit_pull_msg_t  req;
    larpixsim_bit_reply_msg_t rep;
    size_t                    rep_sz;
    int                       rv;

    memset(&req, 0, sizeof(req));
    req.type         = LARPIXSIM_MSG_BIT_PULL;
    req.edge         = (uint8_t)opposite_edge(edge);
    req.requester_id = (uint32_t)opts->id;
    req.seq          = seq;

    rv = nng_send(data_req, &req, sizeof(req), 0);
    if (rv != 0) {
        fprintf(stderr, "chip_larpix[%d] send(bit_pull,%s) failed: %s\n",
            opts->id, edge_name(edge), ERRSTR(rv));
        return -1;
    }

    rep_sz = sizeof(rep);
    rv     = nng_recv(data_req, &rep, &rep_sz, 0);
    if (rv != 0) {
        fprintf(stderr, "chip_larpix[%d] recv(bit_reply,%s) failed: %s\n",
            opts->id, edge_name(edge), ERRSTR(rv));
        return -1;
    }
    if (rep_sz != sizeof(rep) || rep.type != LARPIXSIM_MSG_BIT_REPLY) {
        fprintf(stderr, "chip_larpix[%d] malformed bit reply on %s edge\n", opts->id, edge_name(edge));
        return -1;
    }
    if (rep.seq != seq || rep.edge != (uint8_t)opposite_edge(edge)) {
        fprintf(stderr, "chip_larpix[%d] bit reply mismatch on %s edge\n", opts->id, edge_name(edge));
        return -1;
    }

    *have_bit  = rep.has_bit ? 1u : 0u;
    *bit_value = rep.bit_value ? 1u : 0u;
    return 0;
}

static void
load_charge_stimulus(const std::vector<stimulus_event_t> &events, uint64_t seq, double charge_in[LARPIXSIM_CHANNEL_COUNT])
{
    int i;

    for (i = 0; i < LARPIXSIM_CHANNEL_COUNT; i++) {
        charge_in[i] = 0.0;
    }
    for (const auto &ev : events) {
        if (ev.tick == seq) {
            charge_in[ev.channel] += ev.charge;
        }
    }
}

int
main(int argc, char **argv)
{
    chip_options_t         opts;
    chip_metrics_t         metrics;
    larpixsim_backend_handle_t backend;
    nng_socket             control_rep = NNG_SOCKET_INITIALIZER;
    nng_socket             metric_push = NNG_SOCKET_INITIALIZER;
    nng_socket             data_req[LARPIXSIM_EDGE_COUNT];
    nng_socket             data_rep[LARPIXSIM_EDGE_COUNT];
    bit_server_state_t     bit_state[LARPIXSIM_EDGE_COUNT];
    pthread_t              bit_thread[LARPIXSIM_EDGE_COUNT];
    bool                   bit_state_inited[LARPIXSIM_EDGE_COUNT];
    bool                   bit_thread_started[LARPIXSIM_EDGE_COUNT];
    bool                   has_input[LARPIXSIM_EDGE_COUNT];
    bool                   has_output[LARPIXSIM_EDGE_COUNT];
    uint8_t                published_valid[LARPIXSIM_EDGE_COUNT] = {0, 0, 0, 0};
    uint8_t                published_bits[LARPIXSIM_EDGE_COUNT]  = {0, 0, 0, 0};
    chipsim_trace_writer_t trace;
    std::vector<stimulus_event_t> stimulus_events;
    int                    edge;
    int                    rv;
    int                    exit_code = 1;
    nng_err                init_err;

    memset(&metrics, 0, sizeof(metrics));
    memset(&backend, 0, sizeof(backend));
    memset(&trace, 0, sizeof(trace));
    for (edge = 0; edge < LARPIXSIM_EDGE_COUNT; edge++) {
        data_req[edge] = NNG_SOCKET_INITIALIZER;
        data_rep[edge] = NNG_SOCKET_INITIALIZER;
        bit_state_inited[edge] = false;
        bit_thread_started[edge] = false;
    }

    if (parse_args(argc, argv, &opts) != 0) {
        usage(argv[0]);
        return 2;
    }
    if (load_stimulus_events(&opts, &stimulus_events) != 0) {
        return 1;
    }

    init_err = nng_init(NULL);
    if (init_err != 0) {
        fprintf(stderr, "chip_larpix nng_init failed: %s\n", nng_strerror(init_err));
        return 1;
    }

    if (strcmp(opts.backend_name, "null") == 0) {
        if (larpixsim_backend_create_null(&backend) != 0) {
            goto cleanup;
        }
    } else if (strcmp(opts.backend_name, "cosim") == 0) {
        if (larpixsim_backend_create_cosim(&backend) != 0) {
            goto cleanup;
        }
    } else {
        fprintf(stderr, "chip_larpix[%d] unknown backend '%s'\n", opts.id, opts.backend_name);
        goto cleanup;
    }

    if (chipsim_trace_open(&trace, opts.trace_file, (uint32_t)opts.id) != 0) {
        goto cleanup;
    }

    rv = nng_rep0_open(&control_rep);
    if (rv != 0) {
        fprintf(stderr, "chip_larpix[%d] nng_rep0_open(control) failed: %s\n", opts.id, ERRSTR(rv));
        goto cleanup;
    }
    rv = nng_listen(control_rep, opts.clock_url, NULL, 0);
    if (rv != 0) {
        fprintf(stderr, "chip_larpix[%d] listen(control) failed at %s: %s\n",
            opts.id, opts.clock_url, ERRSTR(rv));
        goto cleanup;
    }

    for (edge = 0; edge < LARPIXSIM_EDGE_COUNT; edge++) {
        has_input[edge] = (opts.in_url[edge] != NULL);
        has_output[edge] = (opts.out_url[edge] != NULL);

        if (has_output[edge]) {
            rv = nng_rep0_open(&data_rep[edge]);
            if (rv != 0) {
                fprintf(stderr, "chip_larpix[%d] open(data_rep,%s) failed: %s\n",
                    opts.id, edge_name(edge), ERRSTR(rv));
                goto cleanup;
            }
            rv = nng_listen(data_rep[edge], opts.out_url[edge], NULL, 0);
            if (rv != 0) {
                fprintf(stderr, "chip_larpix[%d] listen(data_rep,%s) failed at %s: %s\n",
                    opts.id, edge_name(edge), opts.out_url[edge], ERRSTR(rv));
                goto cleanup;
            }
            if (bit_server_init(&bit_state[edge], data_rep[edge], opts.id, edge) != 0) {
                fprintf(stderr, "chip_larpix[%d] bit server init failed on %s edge\n", opts.id, edge_name(edge));
                goto cleanup;
            }
            bit_state_inited[edge] = true;
            if (pthread_create(&bit_thread[edge], NULL, bit_server_thread_main, &bit_state[edge]) != 0) {
                fprintf(stderr, "chip_larpix[%d] bit server thread create failed on %s edge\n", opts.id, edge_name(edge));
                goto cleanup;
            }
            bit_thread_started[edge] = true;
        }

        if (has_input[edge]) {
            rv = nng_req0_open(&data_req[edge]);
            if (rv != 0) {
                fprintf(stderr, "chip_larpix[%d] open(data_req,%s) failed: %s\n", opts.id, edge_name(edge), ERRSTR(rv));
                goto cleanup;
            }
            rv = nng_socket_set_ms(data_req[edge], NNG_OPT_SENDTIMEO, opts.data_timeout_ms);
            if (rv != 0) {
                goto cleanup;
            }
            rv = nng_socket_set_ms(data_req[edge], NNG_OPT_RECVTIMEO, opts.data_timeout_ms);
            if (rv != 0) {
                goto cleanup;
            }
            rv = nng_socket_set_ms(data_req[edge], NNG_OPT_REQ_RESENDTIME, NNG_DURATION_INFINITE);
            if (rv != 0) {
                goto cleanup;
            }
            rv = nng_dial(data_req[edge], opts.in_url[edge], NULL, NNG_FLAG_NONBLOCK);
            if (rv != 0) {
                fprintf(stderr, "chip_larpix[%d] dial(data_req,%s) failed at %s: %s\n",
                    opts.id, edge_name(edge), opts.in_url[edge], ERRSTR(rv));
                goto cleanup;
            }
        }
    }

    rv = nng_push0_open(&metric_push);
    if (rv != 0) {
        fprintf(stderr, "chip_larpix[%d] nng_push0_open(metric) failed: %s\n", opts.id, ERRSTR(rv));
        goto cleanup;
    }
    rv = nng_dial(metric_push, opts.metric_url, NULL, 0);
    if (rv != 0) {
        fprintf(stderr, "chip_larpix[%d] dial(metric) failed: %s\n", opts.id, ERRSTR(rv));
        goto cleanup;
    }

    for (;;) {
        chipsim_tick_msg_t          tick;
        size_t                      tick_sz = sizeof(tick);
        larpixsim_backend_tick_inputs_t  in;
        larpixsim_backend_tick_outputs_t out;

        rv = nng_recv(control_rep, &tick, &tick_sz, 0);
        if (rv != 0) {
            fprintf(stderr, "chip_larpix[%d] recv(control) failed: %s\n", opts.id, ERRSTR(rv));
            goto cleanup;
        }
        if (tick_sz != sizeof(tick)) {
            fprintf(stderr, "chip_larpix[%d] malformed control message\n", opts.id);
            goto cleanup;
        }
        metrics.last_seq = tick.seq;

        if (tick.type == CHIPSIM_MSG_STOP) {
            for (edge = 0; edge < LARPIXSIM_EDGE_COUNT; edge++) {
                if (has_output[edge]) {
                    bit_server_publish(&bit_state[edge], tick.seq, 0u, 0u);
                }
            }
            if (send_done(control_rep, &opts, tick.seq, &metrics) != 0) {
                goto cleanup;
            }
            break;
        }
        if (tick.type != CHIPSIM_MSG_TICK) {
            fprintf(stderr, "chip_larpix[%d] unknown control type=%u\n", opts.id, (unsigned)tick.type);
            goto cleanup;
        }

        for (edge = 0; edge < LARPIXSIM_EDGE_COUNT; edge++) {
            if (has_output[edge]) {
                bit_server_publish(&bit_state[edge], tick.seq, published_valid[edge], published_bits[edge]);
                if (published_valid[edge]) {
                    metrics.tx_count++;
                }
            }
        }

        memset(&in, 0, sizeof(in));
        memset(&out, 0, sizeof(out));
        in.seq = tick.seq;
        in.reset_n = 1u;

        for (edge = 0; edge < LARPIXSIM_EDGE_COUNT; edge++) {
            if (has_input[edge]) {
                if (pull_bit_from_edge(data_req[edge], &opts, edge, tick.seq,
                        &in.rx_bit_valid[edge], &in.rx_bit_value[edge]) != 0) {
                    goto cleanup;
                }
                if (in.rx_bit_valid[edge]) {
                    metrics.rx_count++;
                }
            }
        }

        load_charge_stimulus(stimulus_events, tick.seq, in.charge_in);

        if (backend.vtbl->tick(backend.ctx, &in, &out) != 0) {
            fprintf(stderr, "chip_larpix[%d] backend tick failed at seq=%" PRIu64 "\n", opts.id, tick.seq);
            goto cleanup;
        }

        for (edge = 0; edge < LARPIXSIM_EDGE_COUNT; edge++) {
            published_valid[edge] = out.tx_bit_valid[edge] ? 1u : 0u;
            published_bits[edge]  = out.tx_bit_value[edge] ? 1u : 0u;
        }
        metrics.local_event_count += out.local_event_count;
        metrics.drop_count += out.drop_count;

        if (send_done(control_rep, &opts, tick.seq, &metrics) != 0) {
            goto cleanup;
        }
    }

    if (send_metric(metric_push, &opts, &metrics) != 0) {
        goto cleanup;
    }

    exit_code = 0;

cleanup:
    for (edge = 0; edge < LARPIXSIM_EDGE_COUNT; edge++) {
        if (bit_thread_started[edge]) {
            bit_server_request_stop(&bit_state[edge]);
        }
    }
    for (edge = 0; edge < LARPIXSIM_EDGE_COUNT; edge++) {
        if (nng_socket_id(data_req[edge]) > 0) {
            nng_socket_close(data_req[edge]);
        }
        if (nng_socket_id(data_rep[edge]) > 0) {
            nng_socket_close(data_rep[edge]);
        }
    }
    for (edge = 0; edge < LARPIXSIM_EDGE_COUNT; edge++) {
        if (bit_thread_started[edge]) {
            pthread_join(bit_thread[edge], NULL);
        }
        if (bit_state_inited[edge]) {
            bit_server_destroy(&bit_state[edge]);
        }
    }
    if (nng_socket_id(metric_push) > 0) {
        nng_socket_close(metric_push);
    }
    if (nng_socket_id(control_rep) > 0) {
        nng_socket_close(control_rep);
    }
    chipsim_trace_close(&trace);
    larpixsim_backend_destroy(&backend);
    nng_fini();
    return exit_code;
}
