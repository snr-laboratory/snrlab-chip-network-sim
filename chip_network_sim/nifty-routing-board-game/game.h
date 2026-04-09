#ifndef ROUTING_GAME_H
#define ROUTING_GAME_H

#include <stdint.h>

#ifndef GAME_MAX_W
#define GAME_MAX_W 16
#endif

#ifndef GAME_MAX_H
#define GAME_MAX_H 16
#endif

#ifndef GAME_MAX_HISTORY
#define GAME_MAX_HISTORY 2048
#endif

#define GAME_MAX_CELLS (GAME_MAX_W * GAME_MAX_H)

#ifdef __cplusplus
extern "C" {
#endif

typedef enum GameDir {
    GAME_DIR_NONE = 0,
    GAME_DIR_UP = 1,
    GAME_DIR_RIGHT = 2,
    GAME_DIR_DOWN = 3,
    GAME_DIR_LEFT = 4
} GameDir;

typedef struct GameConfig {
    int width;
    int height;
    int out_x;
    int out_y;
    int history_cap; /* 0 uses GAME_MAX_HISTORY */
    uint32_t seed;   /* 0 becomes 1 to avoid xorshift zero state */
} GameConfig;

typedef struct GameSnap {
    uint8_t occ[GAME_MAX_CELLS];
    uint8_t collided[GAME_MAX_CELLS];
    int eaten;
} GameSnap;

typedef struct Game {
    int width;
    int height;
    int out_x;
    int out_y;

    int turns;
    int eaten;
    int pieces_remaining;

    uint32_t rng_state;

    int history_len;
    int history_cap;

    uint8_t occ[GAME_MAX_CELLS];
    uint8_t dir[GAME_MAX_CELLS];
    uint8_t collided[GAME_MAX_CELLS];

    GameSnap history[GAME_MAX_HISTORY];
} Game;

int game_init(Game *g, GameConfig cfg);
void game_seed(Game *g, uint32_t seed);

void game_clear_all(Game *g);
void game_reset(Game *g);          /* clears pieces + score, keeps routing */
void game_clear_pieces(Game *g);
void game_clear_dirs(Game *g);
void game_reset_history(Game *g);

int game_in_bounds(const Game *g, int x, int y);
int game_index(const Game *g, int x, int y);

int game_get_piece(const Game *g, int x, int y);
void game_set_piece(Game *g, int x, int y, int present);
void game_toggle_piece(Game *g, int x, int y);
int game_get_dir(const Game *g, int x, int y);
void game_set_dir(Game *g, int x, int y, int dir);
void game_cycle_dir(Game *g, int x, int y, int reverse);

uint32_t game_rng_next(Game *g);
int game_rand_range(Game *g, int n);

void game_recount_pieces(Game *g);
void game_place_random_pieces(Game *g, int count);

int game_step(Game *g);  /* returns 1 if ok, 0 if invalid */
int game_undo(Game *g);  /* returns 1 if undone */

int game_score(const Game *g);

void game_fill_routing_row_funnel(Game *g);
void game_fill_routing_col_funnel(Game *g);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* ROUTING_GAME_H */
