; world.asm - game state shared by every module, the static tile tables, and small helpers
; (random numbers, tile lookups, the news ticker).

%include "defs.inc"

global cash, cur_x, cur_y, day, dir_dx, dir_dy, drag, game_over, guest_count, guests, handy_n
global handymen, height, map, msg_buf, n_handy, n_landscape, n_water, next_id, paused, post_msg
global rail_at, rand_n, rating, ride_count, rng, swept, tick, tile_at, tile_cost, tile_joy
global tile_name, tile_nausea, tile_ticket, tile_upkeep, tool, tool_tile, visitors
extern sprintf

section .rdata
dir_dx      db 0, 1, 0, -1
dir_dy      db -1, 0, 1, 0

;                grass path entr stat ferris carou food tree puke track
tile_cost   dd   0,    10,  0,   200, 300,   150,  80,  15,  10,  40
tile_ticket dd   0,    0,   0,   0,   4,     3,    4,   0,   0,   0
tile_joy    dd   0,    0,   0,   0,   20,    15,   10,  0,   0,   0
tile_upkeep dd   0,    0,   0,   20,  15,    8,    4,   0,   0,   2
tile_nausea dd   0,    0,   0,   0,   8,     12,   0,   0,   0,   0
tile_name   dq n_grass, n_path, n_entrance, n_station, n_ferris, n_carousel, n_food, n_tree, n_puke, n_track
tool_tile   db T_PATH, T_STATION, T_TRACK, T_FERRIS, T_CAROUSEL, T_FOOD, T_TREE, TOOL_RAISE, TOOL_LOWER, TOOL_HANDY, T_GRASS   ; T_GRASS = demolish
n_grass     db "Grass", 0
n_path      db "Path", 0
n_entrance  db "Park entrance", 0
n_station   db "Coaster station", 0
n_ferris    db "Ferris wheel", 0
n_carousel  db "Carousel", 0
n_food      db "Food stall", 0
n_tree      db "Tree", 0
n_puke      db "Vomit-covered path", 0
n_track     db "Coaster track", 0
n_handy     db "A handyman", 0
n_water     db "Water", 0
n_landscape db "Landscaping", 0

section .bss
alignb 16
rng         resd 1
cash        resd 1
day         resd 1
tick        resd 1
cur_x       resd 1
cur_y       resd 1
tool        resd 1
drag        resd 1
paused      resd 1
game_over   resd 1
next_id     resd 1
visitors    resd 1
guest_count resd 1
ride_count  resd 1
rating      resd 1
handy_n     resd 1
swept       resd 1
map         resb MAP_SIZE
height      resb MAP_SIZE           ; land height of each tile, 0-MAX_H
handymen    resb MAX_HANDY * HANDY_SIZE
guests      resb MAX_GUESTS * GUEST_SIZE
msg_buf     resb 256

section .text

; uint32 rand() - xorshift32. Leaf; clobbers eax, edx.
rand:
    mov     eax, [rng]
    mov     edx, eax
    shl     edx, 13
    xor     eax, edx
    mov     edx, eax
    shr     edx, 17
    xor     eax, edx
    mov     edx, eax
    shl     edx, 5
    xor     eax, edx
    mov     [rng], eax
    ret

; uint32 rand_n(uint32 n /*ecx*/) -> [0, n). Leaf; clobbers eax, edx only.
rand_n:
    call    rand
    xor     edx, edx
    div     ecx
    mov     eax, edx
    ret

; int tile_at(int x /*ecx*/, int y /*edx*/) -> tile type, or 0xFF off-map.
; Leaf; clobbers eax, r8 (ecx and edx are preserved).
tile_at:
    cmp     ecx, 0
    jl      .oob
    cmp     ecx, MAP_W
    jge     .oob
    cmp     edx, 0
    jl      .oob
    cmp     edx, MAP_H
    jge     .oob
    imul    eax, edx, MAP_W
    add     eax, ecx
    lea     r8, [map]
    movzx   eax, byte [r8 + rax]
    ret
.oob:
    mov     eax, 0xFF
    ret

; int rail_at(int x /*ecx*/, int y /*edx*/) -> 1 if track or station. Leaf.
rail_at:
    call    tile_at
    cmp     eax, T_TRACK
    je      .yes
    cmp     eax, T_STATION
    je      .yes
    xor     eax, eax
    ret
.yes:
    mov     eax, 1
    ret

; void post_msg(const char* fmt /*rcx*/, arg1 /*rdx*/, arg2 /*r8*/) - set the ticker.
post_msg:
    sub     rsp, 40
    mov     r9, r8
    mov     r8, rdx
    mov     rdx, rcx
    lea     rcx, [msg_buf]
    call    sprintf
    add     rsp, 40
    ret
