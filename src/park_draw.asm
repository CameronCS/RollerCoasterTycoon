; park_draw.asm - drawing the park: isometric projection and mouse picking, land and water,
; trees, rides and track, and the people and trains moving over them.

%include "defs.inc"

global anim, draw_person, draw_world, frac, pick_tile
extern box, broken, circ, circle, coaster_n, coasters, cur_x, cur_y, diamond, dir_dx, dir_dy
extern fill_rect, grid, guests, handymen, height, hspan, line, map, pen, pen_left, pen_right
extern pen_top, plot, rail_at, ring, tool, tool_tile, vspan

section .rdata
rail_vx     db 10, 10, -10, -10         ; screen offset from a tile's centre to its edge, per direction
rail_vy     db -5, 5, 5, -5
sin16       db 0, 6, 11, 15, 16, 15, 11, 6, 0, -6, -11, -15, -16, -15, -11, -6
shirts      dd 0xE53935, 0x1E88E5, 0xFDD835, 0x8E24AA, 0xFB8C00, 0x00ACC1, 0xD81B60, 0xF5F5F5

section .bss
alignb 16
frac        resd 1                      ; 0-256: how far into the current tick we are
anim        resd 1                      ; frame counter for animations

section .text

; (eax = sx, edx = gy) iso(int x /*ecx*/, int y /*edx*/) - a tile's top corner on screen. Leaf.
iso:
    mov     eax, ecx
    sub     eax, edx
    imul    eax, eax, HALF_W
    add     eax, OX
    add     edx, ecx
    imul    edx, edx, 10
    add     edx, OY
    ret

; (eax = sx, edx = top y) iso_h(int x /*ecx*/, int y /*edx*/) - a tile's top corner
; on screen, lifted by its land height. Water tiles report their sea bed. Leaf.
iso_h:
    imul    r8d, edx, MAP_W
    add     r8d, ecx
    lea     r9, [height]
    movzx   r8d, byte [r9 + r8]
    call    iso
    shl     r8d, 3                  ; * HSTEP
    sub     edx, r8d
    ret

; (eax = x or -1, edx = y) pick_tile(int px /*ecx*/, int py /*edx*/) - the tile whose
; top surface is under the mouse; front-most first, so hills hide what's behind.
pick_tile:
    push    rbx
    push    rsi
    push    r12
    push    r13
    push    r14
    sub     rsp, 32
    mov     ebx, ecx
    mov     esi, edx
    cmp     esi, HEADER_H
    jl      .miss
    cmp     esi, PANEL_Y
    jge     .miss

    mov     r14d, MAP_W + MAP_H - 2 ; diagonal x + y, front to back
.diagonal:
    mov     r12d, r14d
    cmp     r12d, MAP_W - 1
    jle     .tile
    mov     r12d, MAP_W - 1
.tile:
    mov     r13d, r14d
    sub     r13d, r12d
    cmp     r13d, MAP_H
    jge     .next_diagonal
    mov     ecx, r12d
    mov     edx, r13d
    call    iso_h
    mov     ecx, ebx                ; inside if |dx|/20 + |dy|/10 <= 1
    sub     ecx, eax
    jns     .dx_ok
    neg     ecx
.dx_ok:
    lea     eax, [rdx + 10]
    sub     eax, esi
    jns     .dy_ok
    neg     eax
.dy_ok:
    imul    ecx, ecx, 10
    imul    eax, eax, 20
    add     eax, ecx
    cmp     eax, 200
    jle     .hit
    dec     r12d
    jns     .tile
.next_diagonal:
    dec     r14d
    jns     .diagonal
.miss:
    mov     eax, -1
    jmp     .done
.hit:
    mov     eax, r12d
    mov     edx, r13d
.done:
    add     rsp, 32
    pop     r14
    pop     r13
    pop     r12
    pop     rsi
    pop     rbx
    ret

; void draw_person(int sx /*ecx*/, int feet /*edx*/, int shirt /*r8d*/)
draw_person:
    push    rbx
    push    rsi
    push    rdi
    sub     rsp, 32
    mov     ebx, ecx
    mov     esi, edx
    mov     edi, r8d

    PEN     0x263238                ; legs
    lea     ecx, [rbx - 1]
    lea     edx, [rsi - 4]
    mov     r8d, esi
    call    vspan
    lea     ecx, [rbx + 1]
    lea     edx, [rsi - 4]
    mov     r8d, esi
    call    vspan
    mov     [pen], edi              ; shirt
    lea     ecx, [rbx - 2]
    lea     edx, [rsi - 9]
    mov     r8d, 5
    mov     r9d, 5
    call    fill_rect
    PEN     SKIN
    mov     ecx, ebx
    lea     edx, [rsi - 12]
    mov     r8d, 2
    call    circle
    PEN     0x4E342E                ; hair
    lea     ecx, [rbx - 2]
    lea     edx, [rbx + 3]
    lea     r8d, [rsi - 14]
    call    hspan

    add     rsp, 32
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; void draw_ground(int x /*ecx*/, int y /*edx*/)
draw_ground:
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 32
    mov     r12d, ecx
    mov     r13d, edx
    call    iso
    mov     ebx, eax                ; sx
    mov     esi, edx                ; gy at height 0
    imul    eax, r13d, MAP_W
    add     eax, r12d
    lea     rcx, [map]
    movzx   edi, byte [rcx + rax]
    lea     rcx, [height]
    movzx   r15d, byte [rcx + rax]

    ; a little per-tile shade variation
    mov     eax, r12d
    imul    eax, eax, 7
    mov     ecx, r13d
    imul    ecx, ecx, 13
    xor     eax, ecx
    mov     ecx, r12d
    imul    ecx, r13d
    xor     eax, ecx
    and     eax, 3

    cmp     r15d, SEA_LEVEL
    jb      .water
    cmp     edi, T_PATH
    je      .paved
    cmp     edi, T_PUKE
    je      .paved
    cmp     edi, T_ENTRANCE
    je      .paved
    imul    eax, eax, 0x030502
    lea     r14d, [rax + 0x55A630]  ; grass, over earth cliffs
    mov     edi, 0x4A922A
    mov     dword [pen_left], 0x7A5230
    mov     dword [pen_right], 0x5C3D22
    jmp     .column
.paved:
    imul    eax, eax, 0x020202
    lea     r14d, [rax + 0xA8A29A]  ; path, over stone walls
    mov     edi, 0x857F77
    mov     dword [pen_left], 0x8D8680
    mov     dword [pen_right], 0x6E6862

.column:                            ; the whole column of land, down to the map's base
    cmp     dword [grid], 0
    jne     .grid_lines
    mov     edi, r14d               ; no grid: the lid is all surface colour
.grid_lines:
    mov     [pen_top], edi          ; lid in the grid-line colour...
    mov     ecx, ebx
    lea     edx, [rsi + DIRT_H]
    mov     r8d, HALF_W
    lea     r9d, [r15*HSTEP + DIRT_H]
    call    box
    mov     [pen], r14d             ; ...then the surface inset by a pixel
    mov     ecx, ebx
    mov     edx, r15d
    imul    edx, edx, -HSTEP
    lea     edx, [rsi + rdx + 1]
    mov     r8d, HALF_W - 2
    call    diamond
    jmp     .done

.water:                             ; surface sits a little below the surrounding land
    imul    eax, eax, 0x000306
    add     eax, 0x2E86DE
    mov     [pen_top], eax
    mov     dword [pen_left], 0x1F6FB8
    mov     dword [pen_right], 0x185A96
    mov     ecx, ebx
    lea     edx, [rsi + DIRT_H]
    mov     r8d, HALF_W
    mov     r9d, HSTEP - 3 + DIRT_H
    call    box
    mov     eax, [anim]             ; drifting sparkles
    shr     eax, 3
    imul    ecx, r12d, 3
    add     eax, ecx
    imul    ecx, r13d, 5
    add     eax, ecx
    and     eax, 7
    cmp     eax, 3
    jae     .done
    PEN     0xBBDEFB
    lea     ecx, [rbx + rax*4 - 6]
    lea     edx, [rbx + rax*4]
    lea     r8d, [rsi + rax*2 + 3 - HSTEP + 6]
    call    hspan

.done:
    add     rsp, 32
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; void draw_object(int x /*ecx*/, int y /*edx*/) - whatever stands on the tile
draw_object:
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 48                 ; [rsp+32], [rsp+36], [rsp+40] scratch
    mov     r12d, ecx
    mov     r13d, edx
    call    iso_h
    mov     ebx, eax                ; sx
    mov     esi, edx                ; top of the land (tile centre is esi+10)
    imul    eax, r13d, MAP_W
    add     eax, r12d
    lea     rcx, [map]
    movzx   edi, byte [rcx + rax]
    lea     rcx, [height]
    movzx   r14d, byte [rcx + rax]  ; land height

    cmp     edi, T_TREE
    je      .tree
    cmp     edi, T_PUKE
    je      .puke
    cmp     edi, T_ENTRANCE
    je      .entrance
    cmp     edi, T_STATION
    je      .station
    cmp     edi, T_TRACK
    je      .track
    cmp     edi, T_FERRIS
    je      .ferris
    cmp     edi, T_CAROUSEL
    je      .carousel
    cmp     edi, T_FOOD
    je      .food
    jmp     .done

.tree:
    PEN     0x3E7F24                ; shadow
    lea     ecx, [rbx + 3]
    lea     edx, [rsi + 6]
    mov     r8d, 10
    call    diamond
    PEN     0x5A3A1E                ; trunk
    lea     ecx, [rbx - 1]
    lea     edx, [rsi + 2]
    mov     r8d, 3
    mov     r9d, 10
    call    fill_rect
    mov     eax, r12d               ; two tree sizes
    xor     eax, r13d
    and     eax, 1
    lea     r15d, [rax + 7]
    PEN     0x1B5E20
    mov     ecx, ebx
    lea     edx, [rsi - 1]
    mov     r8d, r15d
    call    circle
    PEN     0x2E7D32
    lea     ecx, [rbx - 1]
    lea     edx, [rsi - 4]
    lea     r8d, [r15 - 2]
    call    circle
    PEN     0x66BB6A
    lea     ecx, [rbx - 3]
    lea     edx, [rsi - 6]
    mov     r8d, 2
    call    circle
    jmp     .done

.puke:
    PEN     0xAFB42B
    lea     ecx, [rbx - 4]
    lea     edx, [rsi + 11]
    mov     r8d, 3
    call    circle
    PEN     0xC0CA33
    lea     ecx, [rbx + 3]
    lea     edx, [rsi + 8]
    mov     r8d, 2
    call    circle
    lea     ecx, [rbx + 6]
    lea     edx, [rsi + 12]
    mov     r8d, 1
    call    circle
    jmp     .done

.entrance:
    BOX_PENS 0xCE93D8, 0x8E24AA, 0x6A1B9A
    lea     ecx, [rbx - 12]
    lea     edx, [rsi + 6]
    mov     r8d, 4
    mov     r9d, 22
    call    box
    lea     ecx, [rbx + 12]
    lea     edx, [rsi + 6]
    mov     r8d, 4
    mov     r9d, 22
    call    box
    PEN     0xD81B60                ; banner
    lea     ecx, [rbx - 16]
    lea     edx, [rsi - 18]
    mov     r8d, 32
    mov     r9d, 7
    call    fill_rect
    PEN     C_ACCENT
    lea     ecx, [rbx - 16]
    lea     edx, [rsi - 18]
    mov     r8d, 32
    mov     r9d, 1
    call    fill_rect
    PEN     0xFFFFFF
    mov     r15d, -12
.bulbs:
    lea     ecx, [rbx + r15]
    lea     edx, [rsi - 15]
    call    plot
    add     r15d, 4
    cmp     r15d, 12
    jle     .bulbs
    jmp     .done

.station:                           ; raised platform level with the track
    BOX_PENS 0xE57373, 0xB71C1C, 0x8E1515
    mov     ecx, ebx
    lea     edx, [rsi + 1]
    mov     r8d, 18
    mov     r9d, RAIL_H
    call    box
    PEN     0xFFFFFF                ; platform edge stripe
    lea     ecx, [rbx - 18]
    lea     edx, [rbx + 18]
    lea     r8d, [rsi + 10 - RAIL_H]
    call    hspan
    jmp     .rails

.track:                             ; support post under the rails, down to land or water
    lea     r15d, [rsi + 11]
    cmp     r14d, SEA_LEVEL
    jae     .post
    sub     r15d, HSTEP - 3
.post:
    PEN     0x9E9E9E
    mov     ecx, ebx
    lea     edx, [rsi + 10 - RAIL_H]
    mov     r8d, r15d
    call    vspan
    PEN     0x616161
    lea     ecx, [rbx + 1]
    lea     edx, [rsi + 10 - RAIL_H]
    mov     r8d, r15d
    call    vspan

.rails:                             ; a rail from the centre towards each connected neighbour
    xor     r15d, r15d
.rail_dir:
    lea     rax, [dir_dx]
    movsx   ecx, byte [rax + r15]
    add     ecx, r12d
    lea     rax, [dir_dy]
    movsx   edx, byte [rax + r15]
    add     edx, r13d
    call    rail_at
    test    eax, eax
    jz      .next_rail
    imul    eax, edx, MAP_W         ; the rail meets its neighbour halfway between their heights
    add     eax, ecx
    lea     rcx, [height]
    movzx   eax, byte [rcx + rax]
    neg     eax
    add     eax, r14d
    imul    eax, eax, HSTEP / 2
    lea     rcx, [rail_vx]
    movsx   ecx, byte [rcx + r15]
    add     ecx, ebx
    mov     [rsp + 32], ecx         ; rail end x
    lea     rcx, [rail_vy]
    movsx   ecx, byte [rcx + r15]
    add     ecx, eax
    lea     ecx, [rcx + rsi + 10 - RAIL_H]
    mov     [rsp + 36], ecx         ; rail end y
    PEN     0x5D0F0F                ; underside
    mov     ecx, ebx
    lea     edx, [rsi + 12 - RAIL_H]
    mov     r8d, [rsp + 32]
    mov     r9d, [rsp + 36]
    add     r9d, 2
    call    line
    PEN     0xFF5252
    mov     ecx, ebx
    lea     edx, [rsi + 10 - RAIL_H]
    mov     r8d, [rsp + 32]
    mov     r9d, [rsp + 36]
    call    line
    PEN     0xD32F2F
    mov     ecx, ebx
    lea     edx, [rsi + 11 - RAIL_H]
    mov     r8d, [rsp + 32]
    mov     r9d, [rsp + 36]
    inc     r9d
    call    line
.next_rail:
    inc     r15d
    cmp     r15d, 4
    jb      .rail_dir
    jmp     .done

.ferris:
    BOX_PENS 0x90A4AE, 0x607D8B, 0x455A64
    mov     ecx, ebx
    lea     edx, [rsi + 3]
    mov     r8d, 12
    mov     r9d, 3
    call    box
    PEN     0xECEFF1                ; A-frame legs
    lea     ecx, [rbx - 9]
    lea     edx, [rsi + 10]
    mov     r8d, ebx
    lea     r9d, [rsi - 16]
    call    line
    lea     ecx, [rbx + 9]
    lea     edx, [rsi + 10]
    mov     r8d, ebx
    lea     r9d, [rsi - 16]
    call    line
    PEN     0x1E88E5                ; rim
    mov     ecx, ebx
    lea     edx, [rsi - 16]
    mov     r8d, 17
    call    ring
    PEN     0x64B5F6
    mov     ecx, ebx
    lea     edx, [rsi - 16]
    mov     r8d, 16
    call    ring
    mov     eax, [anim]             ; rotating spokes and gondolas
    shr     eax, 2
    add     eax, r12d
    and     eax, 15
    mov     [rsp + 40], eax
    xor     r15d, r15d
.spoke:
    mov     eax, [rsp + 40]
    lea     eax, [rax + r15*2]
    and     eax, 15
    lea     rcx, [sin16]
    movsx   edx, byte [rcx + rax]
    lea     edx, [rdx + rsi - 16]
    mov     [rsp + 36], edx         ; spoke end y
    add     eax, 4
    and     eax, 15
    movsx   eax, byte [rcx + rax]
    add     eax, ebx
    mov     [rsp + 32], eax         ; spoke end x
    PEN     0xBBDEFB
    mov     ecx, ebx
    lea     edx, [rsi - 16]
    mov     r8d, [rsp + 32]
    mov     r9d, [rsp + 36]
    call    line
    test    r15d, 1
    jz      .next_spoke
    lea     rax, [shirts]
    mov     eax, [rax + r15*4]
    mov     [pen], eax
    mov     ecx, [rsp + 32]
    sub     ecx, 2
    mov     edx, [rsp + 36]
    mov     r8d, 5
    mov     r9d, 4
    call    fill_rect
.next_spoke:
    inc     r15d
    cmp     r15d, 8
    jb      .spoke
    PEN     0xFFFFFF
    mov     ecx, ebx
    lea     edx, [rsi - 16]
    mov     r8d, 2
    call    circle
    jmp     .done

.carousel:
    BOX_PENS 0xFFE082, 0xFFB300, 0xC68400
    mov     ecx, ebx
    lea     edx, [rsi + 2]
    mov     r8d, 16
    mov     r9d, 4
    call    box
    PEN     0xFFF8E1                ; poles
    lea     ecx, [rbx - 10]
    lea     edx, [rsi - 6]
    lea     r8d, [rsi + 8]
    call    vspan
    lea     ecx, [rbx + 10]
    lea     edx, [rsi - 6]
    lea     r8d, [rsi + 8]
    call    vspan
    lea     ecx, [rbx]
    lea     edx, [rsi - 6]
    lea     r8d, [rsi + 11]
    call    vspan
    mov     eax, [anim]             ; bobbing horses
    shr     eax, 3
    and     eax, 3
    mov     r15d, eax
    PEN     0xFFFFFF
    lea     ecx, [rbx - 8]
    lea     edx, [rsi + r15]
    mov     r8d, 5
    mov     r9d, 3
    call    fill_rect
    PEN     0x8D6E63
    mov     eax, 3
    sub     eax, r15d
    lea     ecx, [rbx + 4]
    lea     edx, [rsi + rax + 1]
    mov     r8d, 5
    mov     r9d, 3
    call    fill_rect
    mov     r15d, 6                 ; striped tent roof, widest ring first
.roof:
    mov     eax, r15d
    and     eax, 1
    mov     eax, 0xE53935
    jz      .roof_colour
    mov     eax, 0xFAFAFA
.roof_colour:
    mov     [pen], eax
    mov     ecx, ebx
    lea     edx, [rsi + r15*2 - 30]
    lea     r8d, [r15*2 + 4]
    call    diamond
    dec     r15d
    jns     .roof
    PEN     0xE53935                ; flag
    mov     ecx, ebx
    lea     edx, [rsi - 37]
    lea     r8d, [rsi - 29]
    call    vspan
    lea     ecx, [rbx + 1]
    lea     edx, [rsi - 37]
    mov     r8d, 5
    mov     r9d, 3
    call    fill_rect
    jmp     .done

.food:
    BOX_PENS 0xD7CCC8, 0xA1887F, 0x795548
    mov     ecx, ebx
    lea     edx, [rsi + 4]
    mov     r8d, 12
    mov     r9d, 10
    call    box
    PEN     0xE53935                ; striped awning
    mov     ecx, ebx
    lea     edx, [rsi - 12]
    mov     r8d, 16
    call    diamond
    PEN     0xFAFAFA
    mov     ecx, ebx
    lea     edx, [rsi - 10]
    mov     r8d, 12
    call    diamond
    PEN     0xE53935
    mov     ecx, ebx
    lea     edx, [rsi - 8]
    mov     r8d, 8
    call    diamond
    PEN     0xFFB300                ; burger sign
    mov     ecx, ebx
    lea     edx, [rsi - 18]
    mov     r8d, 5
    call    circle
    PEN     0x6D4C41
    lea     ecx, [rbx - 5]
    lea     edx, [rsi - 18]
    mov     r8d, 11
    mov     r9d, 2
    call    fill_rect
    PEN     0x7CB342
    lea     ecx, [rbx - 5]
    lea     edx, [rsi - 16]
    mov     r8d, 11
    mov     r9d, 1
    call    fill_rect

.done:                              ; broken down: smoke and a flashing warning sign
    imul    eax, r13d, MAP_W
    add     eax, r12d
    lea     rcx, [broken]
    cmp     byte [rcx + rax], 0
    je      .finished
    mov     r15d, [anim]
    shr     r15d, 1
    and     r15d, 15
    PEN     0x9E9E9E
    lea     ecx, [rbx + 6]
    lea     edx, [rsi - 26]
    sub     edx, r15d
    mov     r8d, 3
    call    circle
    PEN     0x757575
    lea     ecx, [rbx + 9]
    lea     edx, [rsi - 34]
    sub     edx, r15d
    mov     r8d, 2
    call    circle
    test    dword [anim], 8
    jz      .finished
    PEN     0xFFFFFF
    mov     ecx, ebx
    lea     edx, [rsi - 46]
    mov     r8d, 8
    call    circle
    PEN     0xE53935
    mov     ecx, ebx
    lea     edx, [rsi - 46]
    mov     r8d, 7
    call    circle
    PEN     0xFFFFFF                ; "!"
    lea     ecx, [rbx - 1]
    lea     edx, [rsi - 50]
    mov     r8d, 3
    mov     r9d, 6
    call    fill_rect
    lea     ecx, [rbx - 1]
    lea     edx, [rsi - 42]
    mov     r8d, 3
    mov     r9d, 2
    call    fill_rect
.finished:
    add     rsp, 48
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; (eax = sx, edx = centre y) walker_pos(int px /*ecx*/, int py /*edx*/, int x /*r8d*/, int y /*r9d*/)
; - screen position of something moving from tile (px,py) to (x,y), frac of the way there.
walker_pos:
    push    rbx
    push    rsi
    push    rdi
    push    r12
    sub     rsp, 40
    mov     edi, r8d
    mov     r12d, r9d
    call    iso_h
    mov     ebx, eax
    mov     esi, edx
    mov     ecx, edi
    mov     edx, r12d
    call    iso_h
    sub     eax, ebx
    imul    eax, [frac]
    sar     eax, 8
    add     eax, ebx
    sub     edx, esi
    imul    edx, [frac]
    sar     edx, 8
    add     edx, esi
    add     edx, 10
    add     rsp, 40
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; void draw_walkers(int s /*ecx*/) - trains, guests and handymen on diagonal x+y == s
draw_walkers:
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 48
    mov     r15d, ecx

    ; --- train cars ---
    lea     rbx, [coasters]
    xor     esi, esi
.coaster:
    cmp     esi, [coaster_n]
    jae     .guests
    mov     r12d, [rbx + CO_LEN]
    inc     r12d                    ; circuit size
    mov     eax, [rbx + CO_PATH]
    lea     r13, [circ]
    lea     r13, [r13 + rax*2]
    xor     edi, edi                ; car number
.car:
    mov     eax, [rbx + CO_TRAIN]
    sub     eax, edi
    jns     .car_index
    add     eax, r12d
.car_index:
    mov     r14d, eax               ; circuit position of this car
    movzx   eax, word [r13 + r14*2]
    xor     edx, edx
    mov     ecx, MAP_W
    div     ecx                     ; eax = y, edx = x
    mov     [rsp + 32], edx         ; where the car is...
    mov     [rsp + 36], eax
    mov     [rsp + 40], edx         ; ...and where it's coming from
    mov     [rsp + 44], eax
    cmp     dword [rbx + CO_MOVED], 0
    je      .car_diagonal
    mov     eax, r14d
    dec     eax
    jns     .prev_ok
    add     eax, r12d
.prev_ok:
    movzx   eax, word [r13 + rax*2]
    xor     edx, edx
    mov     ecx, MAP_W
    div     ecx
    mov     [rsp + 40], edx
    mov     [rsp + 44], eax
.car_diagonal:                      ; drawn with the later of the two diagonals
    mov     eax, [rsp + 32]
    add     eax, [rsp + 36]
    mov     ecx, [rsp + 40]
    add     ecx, [rsp + 44]
    cmp     eax, ecx
    jge     .car_latest
    mov     eax, ecx
.car_latest:
    cmp     eax, r15d
    jne     .next_car
    mov     ecx, [rsp + 40]
    mov     edx, [rsp + 44]
    mov     r8d, [rsp + 32]
    mov     r9d, [rsp + 36]
    call    walker_pos
    sub     edx, RAIL_H
    mov     [rsp + 32], eax
    mov     [rsp + 36], edx
    BOX_PENS 0xFFD54F, 0xF9A825, 0xC17900
    mov     ecx, eax
    lea     edx, [rdx - 4]
    mov     r8d, 8
    mov     r9d, 5
    call    box
    mov     eax, [rbx + CO_RUN]     ; riders' heads while it's running
    or      eax, [rbx + CO_MOVED]
    jz      .next_car
    PEN     SKIN
    mov     ecx, [rsp + 32]
    sub     ecx, 2
    mov     edx, [rsp + 36]
    sub     edx, 11
    mov     r8d, 2
    call    circle
    mov     ecx, [rsp + 32]
    add     ecx, 3
    mov     edx, [rsp + 36]
    sub     edx, 10
    mov     r8d, 2
    call    circle
.next_car:
    inc     edi
    cmp     edi, TRAIN_CARS
    jb      .car
    add     rbx, CO_SIZE
    inc     esi
    jmp     .coaster

    ; --- guests (riders are on their ride, not the path) ---
.guests:
    lea     rbx, [guests]
    xor     esi, esi
.guest:
    cmp     byte [rbx + G_ACTIVE], 0
    je      .next_guest
    cmp     byte [rbx + G_COOL], 0
    jne     .next_guest
    movzx   r8d, byte [rbx + G_X]
    movzx   r9d, byte [rbx + G_Y]
    movzx   ecx, byte [rbx + G_PX]
    movzx   edx, byte [rbx + G_PY]
    lea     eax, [r8d + r9d]        ; the later of the two diagonals it's between
    lea     r10d, [ecx + edx]
    cmp     eax, r10d
    jge     .guest_latest
    mov     eax, r10d
.guest_latest:
    cmp     eax, r15d
    jne     .next_guest
    call    walker_pos
    mov     r12d, eax
    mov     r13d, edx
    mov     eax, [rbx + G_ID]       ; spread crowds out a little
    imul    ecx, eax, 7
    xor     edx, edx
    mov     eax, ecx
    mov     ecx, 13
    div     ecx
    lea     r12d, [r12d + edx - 6]
    mov     eax, [rbx + G_ID]
    imul    eax, eax, 3
    xor     edx, edx
    mov     ecx, 7
    div     ecx
    lea     r13d, [r13d + edx - 3]
    mov     eax, [rbx + G_ID]
    and     eax, 7
    lea     rcx, [shirts]
    mov     r8d, [rcx + rax*4]
    mov     ecx, r12d
    mov     edx, r13d
    call    draw_person
.next_guest:
    add     rbx, GUEST_SIZE
    inc     esi
    cmp     esi, MAX_GUESTS
    jb      .guest

    ; --- handymen, with brooms ---
    lea     rbx, [handymen]
    xor     esi, esi
.handy:
    cmp     byte [rbx + H_ACTIVE], 0
    je      .next_handy
    movzx   r8d, byte [rbx + H_X]
    movzx   r9d, byte [rbx + H_Y]
    movzx   ecx, byte [rbx + H_PX]
    movzx   edx, byte [rbx + H_PY]
    lea     eax, [r8d + r9d]
    lea     r10d, [ecx + edx]
    cmp     eax, r10d
    jge     .handy_latest
    mov     eax, r10d
.handy_latest:
    cmp     eax, r15d
    jne     .next_handy
    call    walker_pos
    mov     r12d, eax
    mov     r13d, edx
    cmp     byte [rbx + H_TYPE], STAFF_MECH
    je      .mechanic
    PEN     0xA1887F                ; handyman's broom
    lea     ecx, [r12d + 3]
    lea     edx, [r13d - 8]
    lea     r8d, [r12d + 6]
    mov     r9d, r13d
    call    line
    PEN     0xFDD835
    lea     ecx, [r12d + 4]
    lea     edx, [r12d + 9]
    mov     r8d, r13d
    call    hspan
    mov     r8d, HANDY_SHIRT
    jmp     .staff_body
.mechanic:                          ; mechanic's wrench
    PEN     0xB0BEC5
    lea     ecx, [r12d + 3]
    lea     edx, [r13d - 6]
    lea     r8d, [r12d + 7]
    lea     r9d, [r13d - 2]
    call    line
    lea     ecx, [r12d + 7]
    lea     edx, [r13d - 3]
    mov     r8d, 2
    call    circle
    mov     r8d, MECH_SHIRT
.staff_body:
    mov     ecx, r12d
    mov     edx, r13d
    call    draw_person
.next_handy:
    add     rbx, HANDY_SIZE
    inc     esi
    cmp     esi, MAX_HANDY
    jb      .handy

    add     rsp, 48
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; void draw_cursor() - tile outline: green where the tool can be used, red where not
draw_cursor:
    push    rbx
    push    rsi
    sub     rsp, 40
    imul    eax, dword [cur_y], MAP_W
    add     eax, [cur_x]
    lea     rcx, [height]
    movzx   r8d, byte [rcx + rax]
    lea     rcx, [map]
    movzx   ecx, byte [rcx + rax]
    mov     eax, [tool]
    lea     rdx, [tool_tile]
    movzx   eax, byte [rdx + rax]
    mov     edx, 0x69F0AE           ; ok
    cmp     eax, TOOL_HANDY
    je      .handy
    cmp     eax, TOOL_RAISE
    je      .land
    cmp     eax, TOOL_LOWER
    je      .land
    test    eax, eax
    jz      .demolish
    test    ecx, ecx                ; building needs grass...
    jnz     .bad
    cmp     r8d, SEA_LEVEL          ; ...on dry land, unless it's track
    jae     .colour
    cmp     eax, T_TRACK
    je      .colour
    jmp     .bad
.land:
    cmp     ecx, T_GRASS
    je      .colour
    cmp     ecx, T_PATH
    je      .colour
    cmp     ecx, T_PUKE
    je      .colour
    jmp     .bad
.handy:
    cmp     ecx, T_PATH
    je      .colour
    cmp     ecx, T_PUKE
    je      .colour
    cmp     ecx, T_ENTRANCE
    je      .colour
    jmp     .bad
.demolish:
    mov     edx, 0xFFB74D
    test    ecx, ecx
    jz      .bad
    cmp     ecx, T_ENTRANCE
    jne     .colour
.bad:
    mov     edx, 0xFF5252
.colour:
    mov     [pen], edx

    mov     ecx, [cur_x]
    mov     edx, [cur_y]
    call    iso_h
    mov     ebx, eax
    mov     esi, edx
    mov     ecx, ebx                ; top -> right -> bottom -> left -> top
    mov     edx, esi
    lea     r8d, [rbx + HALF_W]
    lea     r9d, [rsi + 10]
    call    line
    lea     ecx, [rbx + HALF_W]
    lea     edx, [rsi + 10]
    mov     r8d, ebx
    lea     r9d, [rsi + 20]
    call    line
    mov     ecx, ebx
    lea     edx, [rsi + 20]
    lea     r8d, [rbx - HALF_W]
    lea     r9d, [rsi + 10]
    call    line
    lea     ecx, [rbx - HALF_W]
    lea     edx, [rsi + 10]
    mov     r8d, ebx
    mov     r9d, esi
    call    line
    add     rsp, 40
    pop     rsi
    pop     rbx
    ret

; void draw_world() - back to front, one diagonal at a time: each tile's land and
; whatever stands on it, then the people and trains on that diagonal. Hills in
; front are drawn later, so they hide what's behind them.
draw_world:
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 40

    xor     r14d, r14d              ; diagonal s = x + y
.diagonal:
    mov     r12d, r14d
    sub     r12d, MAP_H - 1
    jns     .x_ok
    xor     r12d, r12d
.x_ok:
    cmp     r12d, MAP_W
    jge     .walkers
    cmp     r12d, r14d
    jg      .walkers
    mov     r13d, r14d
    sub     r13d, r12d
    mov     ecx, r12d
    mov     edx, r13d
    call    draw_ground
    mov     ecx, r12d
    mov     edx, r13d
    call    draw_object
    inc     r12d
    jmp     .x_ok
.walkers:
    mov     ecx, r14d
    call    draw_walkers
    inc     r14d
    cmp     r14d, MAP_W + MAP_H - 1
    jb      .diagonal

    call    draw_cursor             ; on top, so it's never lost behind a hill

    add     rsp, 40
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
