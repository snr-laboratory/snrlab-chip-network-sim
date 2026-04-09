// Minimal GL enums (subset) and 2D drawing pipeline
#define GL_VERTEX_SHADER              0x8B31
#define GL_FRAGMENT_SHADER            0x8B30
#define GL_ARRAY_BUFFER               0x8892
#define GL_ELEMENT_ARRAY_BUFFER       0x8893
#define GL_STATIC_DRAW                0x88E4
#define GL_FLOAT                      0x1406
#define GL_TRIANGLES                  0x0004
#define GL_UNSIGNED_SHORT             0x1403
#define GL_COLOR_BUFFER_BIT           0x4000

#include "game.h"

// JS interop
extern void js_init(void);
extern void debug_log(const char* s);
extern void set_mode_label(const char* s);

extern int  gl_create_shader(int type);
extern void gl_shader_source(int sid, const char* src);
extern void gl_compile_shader(int sid);
extern int  gl_get_shader_iv(int sid, int pname);
extern void gl_get_shader_info_log(int sid, char* out, int maxLen);

extern int  gl_create_program(void);
extern void gl_attach_shader(int pid, int sid);
extern void gl_link_program(int pid);
extern int  gl_get_program_iv(int pid, int pname);
extern void gl_get_program_info_log(int pid, char* out, int maxLen);
extern void gl_use_program(int pid);
extern int  gl_get_attrib_location(int pid, const char* name);

extern int  gl_gen_buffer(void);
extern void gl_bind_buffer(int target, int bid);
extern void gl_buffer_data(int target, const void* ptr, int byteLen, int usage);
extern void gl_enable_vertex_attrib_array(int loc);
extern void gl_vertex_attrib_pointer(int loc, int size, int type, int normalized, int stride, int offset);

extern int  gl_create_vertex_array(void);
extern void gl_bind_vertex_array(int vid);

extern int  gl_get_uniform_location(int pid, const char* name);
extern void gl_uniform_matrix4fv(int uid, int transpose, const float* m);
extern void gl_uniform1i(int uid, int x);
extern void gl_uniform3f(int uid, float x, float y, float z);
extern void gl_uniform4f(int uid, float x, float y, float z, float w);

extern void gl_viewport(int x, int y, int w, int h);
extern void gl_clear_color(float r, float g, float b, float a);
extern void gl_clear(int mask);
extern void gl_draw_elements(int mode, int count, int type, int offset);
extern void gl_draw_arrays(int mode, int first, int count);
extern unsigned int now_ms(void);

__attribute__((export_name("set_routing_pattern")))
void set_routing_pattern(int kind);

// Minimal libc replacements (avoid JS shims and imports)
typedef unsigned int size_t;
void* memset(void* dst, int val, size_t len){ unsigned char* d=(unsigned char*)dst; unsigned char v=(unsigned char)val; for(size_t i=0;i<len;i++) d[i]=v; return dst; }
void* memcpy(void* dst, const void* src, size_t len){ unsigned char* d=(unsigned char*)dst; const unsigned char* s=(const unsigned char*)src; for(size_t i=0;i<len;i++) d[i]=s[i]; return dst; }
void* memmove(void* dst, const void* src, size_t len){ unsigned char* d=(unsigned char*)dst; const unsigned char* s=(const unsigned char*)src; if(d<s){ for(size_t i=0;i<len;i++) d[i]=s[i]; } else if (d>s){ for(size_t i=len;i>0;i--) d[i-1]=s[i-1]; } return dst; }
int memcmp(const void* a, const void* b, size_t len){ const unsigned char* A=(const unsigned char*)a; const unsigned char* B=(const unsigned char*)b; for(size_t i=0;i<len;i++){ int diff=(int)A[i]-(int)B[i]; if(diff) return diff; } return 0; }

// -------------------------------------------------
// Globals
static int prog;                 // rectangles program
static int u_rect, u_color, u_res;
static int vbo_pos, ebo, vao;
static int a_pos_loc = 0;

static int prog_tri;             // triangles program (pixel coords)
static int u_res_tri, u_color_tri;
static int tri_vao, tri_vbo;
static int a_pos_tri = 0;
static int vp_w = 1, vp_h = 1;

static int running = 0;
static int mode_routing = 0; // 0=placement, 1=routing
static float step_accum = 0.0f;
static float invalid_flash = 0.0f;
static Game game;
static const GameConfig game_default = {
    10, /* width */
    10, /* height */
    5,  /* out_x */
    0,  /* out_y */
    0,  /* history_cap */
    1   /* seed (overridden in init) */
};

// Board layout in pixels (computed per frame)
static float tile_px = 40.0f;
static float board_x = 0.0f, board_y = 0.0f, board_w = 0.0f, board_h = 0.0f;

// -------------------------------------------------
// Utils
static void u32_to_str(unsigned v, char* buf, int n) {
    // quick decimal (not used in UI yet)
    int i=n-1; buf[i--]='\0';
    if (!v) { buf[i]='0'; return; }
    while (v && i>=0) { buf[i--] = '0' + (v%10); v/=10; }
}

static void set_mode_label_js(void) {
    if (mode_routing) set_mode_label("Routing");
    else set_mode_label("Placement");
}

// -------------------------------------------------
// Shader helpers
static char logbuf[1024];
static int make_shader(int type, const char* src) {
    int s = gl_create_shader(type);
    gl_shader_source(s, src);
    gl_compile_shader(s);
    if (!gl_get_shader_iv(s, 0x8B81/*GL_COMPILE_STATUS*/)) {
        gl_get_shader_info_log(s, logbuf, sizeof logbuf);
        debug_log(logbuf);
    }
    return s;
}
static int make_program(const char* vs, const char* fs) {
    int v = make_shader(GL_VERTEX_SHADER, vs);
    int f = make_shader(GL_FRAGMENT_SHADER, fs);
    int p = gl_create_program();
    gl_attach_shader(p, v);
    gl_attach_shader(p, f);
    gl_link_program(p);
    if (!gl_get_program_iv(p, 0x8B82/*GL_LINK_STATUS*/)) {
        gl_get_program_info_log(p, logbuf, sizeof logbuf);
        debug_log(logbuf);
    }
    return p;
}

// -------------------------------------------------
// Simple 2D pipeline (rects in pixel space)
static const char* vs_src =
    "#version 300 es\n"
    "precision mediump float;\n"
    "in vec2 a_pos;\n" // unit quad (0..1)
    "uniform vec4 u_rect;\n"       // x,y,w,h in pixels
    "uniform vec3 u_res;\n"        // viewport w,h,unused
    "void main(){\n"
    "  vec2 p = u_rect.xy + a_pos * u_rect.zw;\n"
    "  vec2 ndc = vec2(p.x / u_res.x * 2.0 - 1.0, 1.0 - p.y / u_res.y * 2.0);\n"
    "  gl_Position = vec4(ndc, 0.0, 1.0);\n"
    "}\n";

static const char* fs_src =
    "#version 300 es\n"
    "precision mediump float;\n"
    "uniform vec4 u_color;\n"
    "out vec4 frag;\n"
    "void main(){ frag = u_color; }\n";

static void draw_rect(float x, float y, float w, float h, float r, float g, float b, float a) {
    gl_bind_vertex_array(vao);
    gl_uniform4f(u_rect, x, y, w, h);
    gl_uniform4f(u_color, r, g, b, a);
    gl_draw_elements(GL_TRIANGLES, 6, GL_UNSIGNED_SHORT, 0);
}

// Triangles (pixel coordinates)
static const char* vs_tri =
    "#version 300 es\n"
    "precision mediump float;\n"
    "in vec2 a_pos;\n"
    "uniform vec3 u_res;\n"
    "void main(){\n"
    "  vec2 ndc = vec2(a_pos.x / u_res.x * 2.0 - 1.0, 1.0 - a_pos.y / u_res.y * 2.0);\n"
    "  gl_Position = vec4(ndc, 0.0, 1.0);\n"
    "}\n";

static void draw_triangle(float x1,float y1,float x2,float y2,float x3,float y3, float r,float g,float b,float a){
    float verts[6] = {x1,y1,x2,y2,x3,y3};
    gl_use_program(prog_tri);
    gl_uniform3f(u_res_tri, (float)vp_w, (float)vp_h, 0.0f);
    gl_uniform4f(u_color_tri, r,g,b,a);
    gl_bind_vertex_array(tri_vao);
    gl_bind_buffer(GL_ARRAY_BUFFER, tri_vbo);
    gl_buffer_data(GL_ARRAY_BUFFER, verts, sizeof(verts), GL_STATIC_DRAW);
    gl_enable_vertex_attrib_array(a_pos_tri);
    gl_vertex_attrib_pointer(a_pos_tri, 2, GL_FLOAT, 0, 2*sizeof(float), 0);
    gl_draw_arrays(GL_TRIANGLES, 0, 3);
    gl_use_program(prog);
}

// -------------------------------------------------
// Rendering helpers
static void compute_layout(void) {
    float margin = 12.0f;
    float usable_w = (float)vp_w - 2.0f * margin;
    float usable_h = (float)vp_h - 2.0f * margin;
    tile_px = (usable_w / (float)game.width);
    if (usable_h / (float)game.height < tile_px) tile_px = usable_h / (float)game.height;
    tile_px = (float)(int)tile_px; // snap to pixel
    board_w = tile_px * (float)game.width;
    board_h = tile_px * (float)game.height;
    board_x = ((float)vp_w - board_w) * 0.5f;
    board_y = ((float)vp_h - board_h) * 0.5f;
}

static void draw_grid(void) {
    // Background
    draw_rect(board_x, board_y, board_w, board_h, 0.18f, 0.18f, 0.22f, 1.0f);

    // Grid lines
    float t = 1.0f; // line thickness in px
    float gx = board_x, gy = board_y;
    for (int i=0;i<=game.width;i++) {
        float x = gx + i*tile_px;
        draw_rect(x, gy, t, board_h, 0.35f, 0.35f, 0.38f, 1.0f);
    }
    for (int j=0;j<=game.height;j++) {
        float y = gy + j*tile_px;
        draw_rect(gx, y, board_w, t, 0.35f, 0.35f, 0.38f, 1.0f);
    }

    // Output tile highlight (yellow border)
    float x = board_x + (float)game.out_x * tile_px;
    float y = board_y + (float)game.out_y * tile_px;
    float m = 2.0f;
    float c = 0.96f;
    draw_rect(x, y, tile_px, m, c, c, 0.20f, 1.0f);
    draw_rect(x, y+tile_px-m, tile_px, m, c, c, 0.20f, 1.0f);
    draw_rect(x, y, m, tile_px, c, c, 0.20f, 1.0f);
    draw_rect(x+tile_px-m, y, m, tile_px, c, c, 0.20f, 1.0f);
}

// (Ports removed for clarity; pipes are solid black)

static void draw_hline(float x0, float x1, float yc, float th){ if (x1<x0){float t=x0;x0=x1;x1=t;} draw_rect(x0, yc - th*0.5f, x1-x0, th, 0,0,0,1); }
static void draw_vline(float y0, float y1, float xc, float th){ if (y1<y0){float t=y0;y0=y1;y1=t;} draw_rect(xc - th*0.5f, y0, th, y1-y0, 0,0,0,1); }

static void draw_arrow(int gx, int gy, int dir) {
    if (dir==GAME_DIR_NONE) return;
    float x = board_x + gx*tile_px;
    float y = board_y + gy*tile_px;
    float m = tile_px * 0.03f;  // very small margin so arrow fills tile
    float t = tile_px * 0.48f;  // thick shaft
    float head = tile_px * 0.56f; // big triangular head
    float cx = x + tile_px*0.5f;
    float cy = y + tile_px*0.5f;

    // Arrows are placed near the tile edge so pieces (centered) do not obscure them
    switch(dir){
        case GAME_DIR_RIGHT: {
            draw_hline(x+m, x+tile_px-m-head*0.9f, cy, t);
            float tipx = x+tile_px-m; float base = tipx - head;
            draw_triangle(tipx,cy, base, cy-head*0.65f, base, cy+head*0.65f, 0,0,0,1);
        } break;
        case GAME_DIR_LEFT: {
            draw_hline(x+m+head*0.9f, x+tile_px-m, cy, t);
            float tipx = x+m; float base = tipx + head;
            draw_triangle(tipx,cy, base, cy+head*0.65f, base, cy-head*0.65f, 0,0,0,1);
        } break;
        case GAME_DIR_UP: {
            draw_vline(y+m+head*0.9f, y+tile_px-m, cx, t);
            float tipy = y+m; float base = tipy + head;
            draw_triangle(cx,tipy, cx+head*0.65f, base, cx-head*0.65f, base, 0,0,0,1);
        } break;
        case GAME_DIR_DOWN: {
            draw_vline(y+m, y+tile_px-m-head*0.9f, cx, t);
            float tipy = y+tile_px-m; float base = tipy - head;
            draw_triangle(cx,tipy, cx-head*0.65f, base, cx+head*0.65f, base, 0,0,0,1);
        } break;
    }
}

static void draw_piece(int gx, int gy) {
    float x = board_x + gx*tile_px;
    float y = board_y + gy*tile_px;
    float s = tile_px * 0.38f;
    float px = x + (tile_px - s)*0.5f;
    float py = y + (tile_px - s)*0.5f;
    if (game.collided[game_index(&game, gx, gy)])
        draw_rect(px, py, s, s, 0.85f, 0.25f, 0.35f, 1.0f); // red for this turn
    else
        draw_rect(px, py, s, s, 0.22f, 0.45f, 0.98f, 1.0f);
}

static void place_random_pieces(int count){
    game_place_random_pieces(&game, count);
}

// -------------------------------------------------
// HUD: simple 7-seg digits and letters (T,E,S,P)
static void draw_seg_h(float x,float y,float w,float t,float r,float g,float b,float a){ draw_rect(x,y,w,t,r,g,b,a);} // horizontal
static void draw_seg_v(float x,float y,float t,float h,float r,float g,float b,float a){ draw_rect(x,y,t,h,r,g,b,a);} // vertical

static void draw_digit7(int d, float x, float y, float scale, float r, float g, float b, float a){
    float w = 10.0f*scale, t = 2.0f*scale, gap = 1.0f*scale;
    float h = 16.0f*scale;
    // segments positions
    // a top, b upper-right, c lower-right, d bottom, e lower-left, f upper-left, g middle
    int on=1, off=0;
    int segs[10][7]={{1,1,1,1,1,1,0},{0,1,1,0,0,0,0},{1,1,0,1,1,0,1},{1,1,1,1,0,0,1},{0,1,1,0,0,1,1},{1,0,1,1,0,1,1},{1,0,1,1,1,1,1},{1,1,1,0,0,0,0},{1,1,1,1,1,1,1},{1,1,1,1,0,1,1}};
    int* S = segs[d%10];
    if (S[0]) draw_seg_h(x, y, w, t, r,g,b,a); // a
    if (S[1]) draw_seg_v(x+w-t, y+gap, t, h/2-gap*2, r,g,b,a); // b
    if (S[2]) draw_seg_v(x+w-t, y+h/2+gap, t, h/2-gap*2, r,g,b,a); // c
    if (S[3]) draw_seg_h(x, y+h-t, w, t, r,g,b,a); // d
    if (S[4]) draw_seg_v(x, y+h/2+gap, t, h/2-gap*2, r,g,b,a); // e
    if (S[5]) draw_seg_v(x, y+gap, t, h/2-gap*2, r,g,b,a); // f
    if (S[6]) draw_seg_h(x, y+h/2-t/2, w, t, r,g,b,a); // g
}

static float draw_number(int n, float x, float y, float scale, float r, float g, float b, float a){
    if (n<0) n=0; // not handling minus
    int digits[12]; int cnt=0; do { digits[cnt++]=n%10; n/=10; } while(n && cnt<12);
    float advance = (10.0f*scale) + (4.0f*scale);
    for (int i=cnt-1;i>=0;--i){ draw_digit7(digits[i], x, y, scale, r,g,b,a); x += advance; }
    return x; // return pen x
}

static void draw_letter_T(float x,float y,float s){ float w=10*s,t=2*s; draw_rect(x,y,w,t,1,1,1,1); draw_rect(x+w/2-t/2,y,t,16*s,1,1,1,1);}
static void draw_letter_E(float x,float y,float s){ float w=10*s,t=2*s; draw_rect(x,y,t,16*s,1,1,1,1); draw_rect(x,y,w,t,1,1,1,1); draw_rect(x,y+8*s-t/2,w*0.8f,t,1,1,1,1); draw_rect(x,y+16*s-t,w,t,1,1,1,1);}
static void draw_letter_S(float x,float y,float s){ float w=10*s,t=2*s; draw_rect(x,y,w,t,1,1,1,1); draw_rect(x,y+8*s-t/2,w,t,1,1,1,1); draw_rect(x,y+16*s-t,w,t,1,1,1,1); draw_rect(x,y+t, t, 6*s,1,1,1,1); draw_rect(x+w-t,y+8*s, t, 6*s,1,1,1,1);}
static void draw_letter_P(float x,float y,float s){ float w=10*s,t=2*s; draw_rect(x,y,t,16*s,1,1,1,1); draw_rect(x,y,w,t,1,1,1,1); draw_rect(x+w-t,y+t, t, 6*s,1,1,1,1); draw_rect(x,y+8*s-t/2,w,t,1,1,1,1);}

static void draw_hud(void){
    // Scale HUD relative to tile size; clamp and reduce to ~80%
    float pad = 8.0f;
    float s = tile_px * 0.12f; if (s < 3.0f) s = 3.0f; if (s > 6.0f) s = 6.0f; s *= 0.8f;
    float k = s / 1.2f; // scale relative to original sizing
    float panel_w = 160.0f * k;
    float panel_h = 56.0f * k;

    // Prefer right side of the board; otherwise left; always clamp on screen
    float x = board_x + board_w + pad;
    if (x + panel_w + pad > (float)vp_w) x = board_x - panel_w - pad;
    if (x < pad) x = (float)vp_w - panel_w - pad;
    if (x < pad) x = pad; // final clamp

    // Align vertically with board top, clamp to screen
    float y = board_y;
    if (y < pad) y = pad;
    if (y + panel_h + pad > (float)vp_h) y = (float)vp_h - panel_h - pad;

    // Softer contrast background and slightly dimmer text
    draw_rect(x-6, y-6, panel_w, panel_h, 0.00f, 0.00f, 0.00f, 0.25f);
    float px = x, py=y;
    // T: turns
    draw_letter_T(px, py, s); px += 16*s; px = draw_number(game.turns, px, py, s, 0.88f,0.88f,0.90f,1.0f);
    // E: eaten
    px = x; py += 18*s; draw_letter_E(px, py, s); px += 16*s; px = draw_number(game.eaten, px, py, s, 0.88f,0.88f,0.90f,1.0f);
    // S: score
    int score = game_score(&game); px = x; py += 18*s; draw_letter_S(px, py, s); px += 16*s; px = draw_number(score, px, py, s, 0.88f,0.88f,0.90f,1.0f);
    // P: pieces (first row to the right)
    px = x + (90.0f * k); py = y; draw_letter_P(px, py, s); px += 16*s; draw_number(game.pieces_remaining, px, py, s, 0.60f,0.80f,0.90f,1.0f);
}

// -------------------------------------------------
// Routing + Simulation
static int step_once(void) {
    if (!game_step(&game)) {
        invalid_flash = 0.65f;
        return 0;
    }
    if (game.pieces_remaining == 0) running = 0;
    return 1;
}

// -------------------------------------------------
// Input
static int mouse_down = 0;
static int last_tx=-1, last_ty=-1;

static void ensure_tile_from_xy(int px, int py, int* tx, int* ty){
    if (px < board_x || py < board_y || px >= board_x+board_w || py >= board_y+board_h) { *tx=-1; *ty=-1; return; }
    *tx = (int)((px - board_x)/tile_px);
    *ty = (int)((py - board_y)/tile_px);
    if (*tx<0||*tx>=game.width||*ty<0||*ty>=game.height) { *tx=-1; *ty=-1; }
}

// removed shape cycling (now single direction per tile)

__attribute__((export_name("on_pointer")))
void on_pointer(int x, int y, int type, int buttons, int mods) {
    if (type==1) { mouse_down = 1; last_tx = -1; last_ty = -1; }
    else if (type==2) { mouse_down = 0; last_tx = -1; last_ty = -1; }
    int tx, ty; ensure_tile_from_xy(x,y,&tx,&ty);
    if (!mouse_down || tx<0) return;
    // Avoid repeats only for move events; allow repeated clicks on same tile
    if (type==0 && tx==last_tx && ty==last_ty) return;
    int reverse = (mods & 1) ? 1 : 0; // shift = reverse cycle
    if (!mode_routing) {
        // Placement: toggle piece
        game_toggle_piece(&game, tx, ty);
        game_reset_history(&game); // editing invalidates history
    } else {
        // Routing: cycle direction
        game_cycle_dir(&game, tx, ty, reverse);
        game_reset_history(&game); // editing invalidates history
    }
    last_tx = tx; last_ty = ty;
}

__attribute__((export_name("on_key")))
void on_key(int code, int down) {
    if (!down) return;
    if (code=='M') { // toggle mode
        mode_routing = !mode_routing; set_mode_label_js();
    } else if (code==' '||code==32) {
        running = !running;
    } else if (code=='S') {
        (void)step_once();
    } else if (code=='Z') {
        if (game_undo(&game)) running = 0;
    } else if (code=='R') {
        // reset state but keep routing
        game_reset(&game);
        running=0; invalid_flash=0.0f;
    } else if (code=='C') {
        game_clear_pieces(&game);
        game_reset_history(&game);
    } else if (code=='D') {
        game_clear_dirs(&game);
        game_reset_history(&game);
    } else if (code=='F') {
        set_routing_pattern(0);
    } else if (code=='G') {
        set_routing_pattern(1);
    } else if (code>='0' && code<='9') {
        int n = (code=='0') ? 10 : (code - '0');
        place_random_pieces(n);
        game.turns = 0;
        game.eaten = 0;
        running=0; invalid_flash=0.0f;
        game_reset_history(&game);
    }
}

// -------------------------------------------------
// Exports
__attribute__((export_name("set_viewport")))
void set_viewport(int w, int h) { vp_w=w; vp_h=h; }

__attribute__((export_name("set_routing_pattern")))
void set_routing_pattern(int kind) {
    if (kind == 0) {
        game_fill_routing_row_funnel(&game);
    } else if (kind == 1) {
        game_fill_routing_col_funnel(&game);
    } else {
        return;
    }
    game_reset_history(&game);
}

__attribute__((export_name("set_game_config")))
int set_game_config(int w, int h, int out_x, int out_y, int seed, int history_cap) {
    GameConfig cfg = game_default;
    if (w > 0) cfg.width = w;
    if (h > 0) cfg.height = h;
    if (out_x >= 0) cfg.out_x = out_x;
    if (out_y >= 0) cfg.out_y = out_y;
    if (history_cap > 0) cfg.history_cap = history_cap;
    cfg.seed = (uint32_t)seed;

    if (!game_init(&game, cfg)) return 0;
    if (seed == 0) {
        game_seed(&game, now_ms() ^ 0xA53u);
    }
    running = 0;
    invalid_flash = 0.0f;
    step_accum = 0.0f;
    return 1;
}

__attribute__((export_name("init")))
void init(void) {
    js_init();
    set_mode_label_js();

    // Program
    prog = make_program(vs_src, fs_src);
    gl_use_program(prog);
    u_rect  = gl_get_uniform_location(prog, "u_rect");
    u_color = gl_get_uniform_location(prog, "u_color");
    u_res   = gl_get_uniform_location(prog, "u_res");
    a_pos_loc = gl_get_attrib_location(prog, "a_pos");

    // Unit quad
    float quad[8] = {0,0, 1,0, 0,1, 1,1};
    unsigned short idx[6] = {0,1,2, 2,1,3};
    vao = gl_create_vertex_array();
    gl_bind_vertex_array(vao);
    vbo_pos = gl_gen_buffer();
    gl_bind_buffer(GL_ARRAY_BUFFER, vbo_pos);
    gl_buffer_data(GL_ARRAY_BUFFER, quad, sizeof(quad), GL_STATIC_DRAW);
    gl_enable_vertex_attrib_array(a_pos_loc);
    gl_vertex_attrib_pointer(a_pos_loc, 2, GL_FLOAT, 0, 2*sizeof(float), 0);
    ebo = gl_gen_buffer();
    gl_bind_buffer(GL_ELEMENT_ARRAY_BUFFER, ebo);
    gl_buffer_data(GL_ELEMENT_ARRAY_BUFFER, idx, sizeof(idx), GL_STATIC_DRAW);

    // Triangles program
    prog_tri = make_program(vs_tri, fs_src);
    u_res_tri   = gl_get_uniform_location(prog_tri, "u_res");
    u_color_tri = gl_get_uniform_location(prog_tri, "u_color");
    tri_vao = gl_create_vertex_array();
    gl_bind_vertex_array(tri_vao);
    tri_vbo = gl_gen_buffer();
    gl_bind_buffer(GL_ARRAY_BUFFER, tri_vbo);
    a_pos_tri = gl_get_attrib_location(prog_tri, "a_pos");
    gl_enable_vertex_attrib_array(a_pos_tri);
    gl_vertex_attrib_pointer(a_pos_tri, 2, GL_FLOAT, 0, 2*sizeof(float), 0);

    if (!game_init(&game, game_default)) {
        debug_log("game_init failed");
    }
    game_seed(&game, now_ms() ^ 0xA53u);
}

__attribute__((export_name("frame")))
void frame(float dt) {
    if (invalid_flash>0.0f) { invalid_flash -= dt; if (invalid_flash<0) invalid_flash=0; }
    if (running) {
        step_accum += dt;
        const float step_hz = 0.35f;
        while (step_accum >= step_hz) {
            if (!step_once()) { running=0; break; }
            step_accum -= step_hz;
        }
    }

    compute_layout();
    gl_use_program(prog);
    gl_uniform3f(u_res, (float)vp_w, (float)vp_h, 0.0f);
    gl_clear(GL_COLOR_BUFFER_BIT);

    draw_grid();
    // Arrows then pieces
    for (int y=0;y<game.height;y++) {
        for (int x=0;x<game.width;x++) {
            draw_arrow(x, y, game_get_dir(&game, x, y));
        }
    }
    for (int y=0;y<game.height;y++) {
        for (int x=0;x<game.width;x++) {
            if (game.occ[game_index(&game, x, y)]) draw_piece(x, y);
        }
    }
    draw_hud();

    // Invalid flash overlay
    if (invalid_flash>0.0f) {
        float a = invalid_flash * 0.8f;
        draw_rect(board_x, board_y, board_w, board_h, 0.9f, 0.2f, 0.2f, a);
    }
}
