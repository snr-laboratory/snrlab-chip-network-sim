#include "game.h"

static int game_min_int(int a, int b) { return a < b ? a : b; }

int game_in_bounds(const Game *g, int x, int y) {
    return x >= 0 && y >= 0 && x < g->width && y < g->height;
}

int game_index(const Game *g, int x, int y) {
    return y * g->width + x;
}

void game_seed(Game *g, uint32_t seed) {
    g->rng_state = seed ? seed : 1u;
}

uint32_t game_rng_next(Game *g) {
    uint32_t x = g->rng_state;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    g->rng_state = x ? x : 1u;
    return g->rng_state;
}

int game_rand_range(Game *g, int n) {
    if (n <= 0) return 0;
    return (int)(game_rng_next(g) % (uint32_t)n);
}

static void game_clear_cells(uint8_t *cells, int count) {
    for (int i = 0; i < count; ++i) cells[i] = 0;
}

void game_reset_history(Game *g) {
    g->history_len = 0;
}

void game_recount_pieces(Game *g) {
    int cells = g->width * g->height;
    int count = 0;
    for (int i = 0; i < cells; ++i) if (g->occ[i]) count++;
    g->pieces_remaining = count;
}

void game_clear_pieces(Game *g) {
    int cells = g->width * g->height;
    game_clear_cells(g->occ, cells);
    game_clear_cells(g->collided, cells);
    g->pieces_remaining = 0;
}

void game_clear_dirs(Game *g) {
    int cells = g->width * g->height;
    game_clear_cells(g->dir, cells);
}

void game_clear_all(Game *g) {
    int cells = g->width * g->height;
    game_clear_cells(g->occ, cells);
    game_clear_cells(g->collided, cells);
    game_clear_cells(g->dir, cells);
    g->turns = 0;
    g->eaten = 0;
    g->pieces_remaining = 0;
    g->history_len = 0;
}

void game_reset(Game *g) {
    int cells = g->width * g->height;
    game_clear_cells(g->occ, cells);
    game_clear_cells(g->collided, cells);
    g->turns = 0;
    g->eaten = 0;
    g->pieces_remaining = 0;
    g->history_len = 0;
}

int game_init(Game *g, GameConfig cfg) {
    if (!g) return 0;
    if (cfg.width <= 0 || cfg.height <= 0) return 0;
    if (cfg.width > GAME_MAX_W || cfg.height > GAME_MAX_H) return 0;
    if (cfg.out_x < 0 || cfg.out_x >= cfg.width) return 0;
    if (cfg.out_y < 0 || cfg.out_y >= cfg.height) return 0;

    g->width = cfg.width;
    g->height = cfg.height;
    g->out_x = cfg.out_x;
    g->out_y = cfg.out_y;
    g->turns = 0;
    g->eaten = 0;
    g->pieces_remaining = 0;
    g->history_len = 0;
    g->history_cap = cfg.history_cap > 0 ? game_min_int(cfg.history_cap, GAME_MAX_HISTORY) : GAME_MAX_HISTORY;

    game_seed(g, cfg.seed);
    game_clear_all(g);
    return 1;
}

int game_get_piece(const Game *g, int x, int y) {
    if (!game_in_bounds(g, x, y)) return 0;
    return g->occ[game_index(g, x, y)] ? 1 : 0;
}

void game_set_piece(Game *g, int x, int y, int present) {
    if (!game_in_bounds(g, x, y)) return;
    int idx = game_index(g, x, y);
    int was = g->occ[idx] ? 1 : 0;
    g->occ[idx] = present ? 1 : 0;
    if (was != present) {
        g->pieces_remaining += present ? 1 : -1;
    }
}

void game_toggle_piece(Game *g, int x, int y) {
    if (!game_in_bounds(g, x, y)) return;
    int idx = game_index(g, x, y);
    int now = g->occ[idx] ? 0 : 1;
    g->occ[idx] = (uint8_t)now;
    g->pieces_remaining += now ? 1 : -1;
}

int game_get_dir(const Game *g, int x, int y) {
    if (!game_in_bounds(g, x, y)) return GAME_DIR_NONE;
    return g->dir[game_index(g, x, y)];
}

void game_set_dir(Game *g, int x, int y, int dir) {
    if (!game_in_bounds(g, x, y)) return;
    g->dir[game_index(g, x, y)] = (uint8_t)dir;
}

void game_cycle_dir(Game *g, int x, int y, int reverse) {
    if (!game_in_bounds(g, x, y)) return;
    int order[] = { GAME_DIR_NONE, GAME_DIR_UP, GAME_DIR_RIGHT, GAME_DIR_DOWN, GAME_DIR_LEFT };
    int n = 5;
    int idx = 0;
    int cur = game_get_dir(g, x, y);
    for (int i = 0; i < n; ++i) {
        if (order[i] == cur) { idx = i; break; }
    }
    idx = reverse ? (idx - 1 + n) % n : (idx + 1) % n;
    game_set_dir(g, x, y, order[idx]);
}

void game_place_random_pieces(Game *g, int count) {
    int cells = g->width * g->height;
    if (count < 0) count = 0;
    if (count > cells) count = cells;

    game_clear_cells(g->occ, cells);
    game_clear_cells(g->collided, cells);

    int pool[GAME_MAX_CELLS];
    for (int i = 0; i < cells; ++i) pool[i] = i;
    for (int i = cells - 1; i > 0; --i) {
        int j = game_rand_range(g, i + 1);
        int t = pool[i]; pool[i] = pool[j]; pool[j] = t;
    }
    for (int i = 0; i < count; ++i) {
        g->occ[pool[i]] = 1;
    }
    g->pieces_remaining = count;
}

static void game_push_history(Game *g) {
    if (g->history_len >= g->history_cap) return;
    int cells = g->width * g->height;
    GameSnap *snap = &g->history[g->history_len];
    for (int i = 0; i < cells; ++i) {
        snap->occ[i] = g->occ[i];
        snap->collided[i] = g->collided[i];
    }
    snap->eaten = g->eaten;
    g->history_len++;
}

int game_undo(Game *g) {
    if (g->history_len <= 0) return 0;
    g->history_len--;
    int cells = g->width * g->height;
    GameSnap *snap = &g->history[g->history_len];
    for (int i = 0; i < cells; ++i) {
        g->occ[i] = snap->occ[i];
        g->collided[i] = snap->collided[i];
    }
    g->eaten = snap->eaten;
    if (g->turns > 0) g->turns--;
    game_recount_pieces(g);
    return 1;
}

static int game_dx_for(int dir) {
    return dir == GAME_DIR_RIGHT ? 1 : dir == GAME_DIR_LEFT ? -1 : 0;
}

static int game_dy_for(int dir) {
    return dir == GAME_DIR_DOWN ? 1 : dir == GAME_DIR_UP ? -1 : 0;
}

int game_step(Game *g) {
    game_push_history(g);

    int out_idx = game_index(g, g->out_x, g->out_y);
    if (g->occ[out_idx]) g->occ[out_idx] = 0;

    int cells = g->width * g->height;
    uint16_t nextc[GAME_MAX_CELLS];
    for (int i = 0; i < cells; ++i) { nextc[i] = 0; g->collided[i] = 0; }

    for (int y = 0; y < g->height; ++y) {
        for (int x = 0; x < g->width; ++x) {
            int idx = game_index(g, x, y);
            if (!g->occ[idx]) continue;
            int dir = g->dir[idx];
            if (dir == GAME_DIR_NONE) return 0;
            int nx = x + game_dx_for(dir);
            int ny = y + game_dy_for(dir);
            if (!game_in_bounds(g, nx, ny)) return 0;
            nextc[game_index(g, nx, ny)]++;
        }
    }

    int new_eaten = 0;
    int remaining = 0;
    for (int i = 0; i < cells; ++i) {
        uint16_t c = nextc[i];
        if (c == 0) {
            g->occ[i] = 0;
        } else {
            if (c > 1) {
                new_eaten += (int)c - 1;
                g->collided[i] = 1;
            }
            g->occ[i] = 1;
            remaining++;
        }
    }
    g->eaten += new_eaten;
    g->turns++;
    g->pieces_remaining = remaining;
    return 1;
}

int game_score(const Game *g) {
    return g->turns + 2 * g->eaten;
}

void game_fill_routing_row_funnel(Game *g) {
    if (!g) return;
    for (int y = 0; y < g->height; ++y) {
        for (int x = 0; x < g->width; ++x) {
            int dir = GAME_DIR_NONE;
            if (y < g->out_y) {
                dir = GAME_DIR_DOWN;
            } else if (y > g->out_y) {
                dir = GAME_DIR_UP;
            } else {
                if (x < g->out_x) dir = GAME_DIR_RIGHT;
                else if (x > g->out_x) dir = GAME_DIR_LEFT;
                else dir = GAME_DIR_UP;
            }
            g->dir[game_index(g, x, y)] = (uint8_t)dir;
        }
    }
}

void game_fill_routing_col_funnel(Game *g) {
    if (!g) return;
    for (int y = 0; y < g->height; ++y) {
        for (int x = 0; x < g->width; ++x) {
            int dir = GAME_DIR_NONE;
            if (x < g->out_x) {
                dir = GAME_DIR_RIGHT;
            } else if (x > g->out_x) {
                dir = GAME_DIR_LEFT;
            } else {
                if (y < g->out_y) dir = GAME_DIR_DOWN;
                else if (y > g->out_y) dir = GAME_DIR_UP;
                else dir = GAME_DIR_UP;
            }
            g->dir[game_index(g, x, y)] = (uint8_t)dir;
        }
    }
}
