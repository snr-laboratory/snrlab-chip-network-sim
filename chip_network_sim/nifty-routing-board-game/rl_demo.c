#include <stdio.h>
#include "game.h"

int main(void) {
    Game g;
    GameConfig cfg = {
        .width       = 10,
        .height      = 10,
        .out_x       = 5,
        .out_y       = 0,
        .history_cap = 0,
        .seed        = 123u,
    };

    if (!game_init(&g, cfg)) {
        fprintf(stderr, "game_init failed\n");
        return 1;
    }

    game_place_random_pieces(&g, 20);
    game_fill_routing_row_funnel(&g);

    int guard = 1000;
    while (g.pieces_remaining > 0 && guard-- > 0) {
        if (!game_step(&g)) {
            fprintf(stderr, "invalid routing at turn %d\n", g.turns);
            break;
        }
    }

    printf("Turns: %d\n", g.turns);
    printf("Eaten: %d\n", g.eaten);
    printf("Score: %d\n", game_score(&g));
    return 0;
}
