; ui.asm - the interface around the park: header, toolbar, info lines, game-over
; banner, fonts and text, and composing each frame.

%include "defs.inc"

global draw_text, font_big, font_norm, font_small, font_title, make_font, render, use_font
extern broken, cash, coaster_n, coaster_of, coasters, CreateFontA, cur_x, cur_y, day, diamond, drag
extern draw_options, draw_person, draw_world, fill_rect, game_over, GdiFlush, guest_count, handy_n
extern hdc_mem, height, line, map, mech_n, msg_buf, n_water, paused, pen, price, rating, ride_value
extern SelectObject, SetTextColor, sound_on, sprintf, TextOutA, tile_name, tile_upkeep, tool, vspan

section .rdata
tool_name   dq tn_path, tn_station, tn_track, tn_ferris, tn_carousel, tn_food, tn_tree, tn_raise, tn_lower, tn_handy, tn_mech, tn_demolish
tool_price  dq tp_path, tp_station, tp_track, tp_ferris, tp_carousel, tp_food, tp_tree, tp_land, tp_land, tp_handy, tp_mech, tp_demolish
tool_icon   dd 0xA8A29A, 0xC62828, 0x7F1010, 0x42A5F5, 0xFFB300, 0x8D6E63, 0x2E7D32, 0x8D6E63, 0x8D6E63, 0, 0, 0
go_title    dq 0, go_win, go_lose, go_bankrupt
go_sub      dq 0, go_win_sub, go_lose_sub, go_bankrupt_sub
go_colour   dd 0, 0x2E7D32, 0xB71C1C, 0xB71C1C
font_face   db "Segoe UI", 0
tn_path     db "Path", 0
tn_station  db "Station", 0
tn_track    db "Track", 0
tn_ferris   db "Ferris", 0
tn_carousel db "Carousel", 0
tn_food     db "Food", 0
tn_tree     db "Tree", 0
tn_raise    db "Raise", 0
tn_lower    db "Lower", 0
tn_handy    db "Handyman", 0
tn_mech     db "Mechanic", 0
tn_demolish db "Demolish", 0
tp_path     db "$10", 0
tp_station  db "$200", 0
tp_track    db "$40 / tile", 0
tp_ferris   db "$300", 0
tp_carousel db "$150", 0
tp_food     db "$80", 0
tp_tree     db "$15", 0
tp_land     db "$20", 0
tp_handy    db "$100", 0
tp_mech     db "$150", 0
tp_demolish db "right-click", 0
go_win      db "SCENARIO COMPLETE!", 0
go_lose     db "SCENARIO FAILED", 0
go_bankrupt db "BANKRUPT!", 0
go_win_sub  db "Your park is a smash hit.   Press R to play again, Esc to quit.", 0
go_lose_sub db "Not enough guests by the deadline.   Press R to retry, Esc to quit.", 0
go_bankrupt_sub db "The bank has repossessed your park.   Press R to retry, Esc to quit.", 0
s_title     db "RollerCoaster Tycoon .asm", 0
s_paused    db "PAUSED", 0
f_header    db "Day %d of %d     Cash $%d     Guests %d / %d     Staff %d     Rating %d%%     Coasters %d", 0
f_cursor    db "Tile (%d,%d), height %d: %s", 0
f_rideinfo  db "  -  price $%d (worth about $%d), upkeep $%d/day%s", 0
f_coaster   db "  -  %d track, %d turns, %d drops, %d over water, excitement %d  -  price $%d (worth about $%d)%s", 0
s_price_hint db "      scroll or +/- to change the price", 0
s_broken    db "      BROKEN DOWN - send a mechanic", 0
s_no_loop   db "  -  not open: the track must loop back into the station", 0
s_loose     db "  -  not part of a finished circuit", 0
f_help      db "Click/drag: build    Right-click: demolish    1-9, 0, M, X: tools    Scroll or +/-: ride price    B: drag-build [%s]    P: pause    N: sound [%s]    O: options    F5 / F9: save / load    Esc: quit", 0
s_on        db "on", 0
s_off       db "off", 0

section .bss
alignb 16
font_title  resq 1
font_norm   resq 1
font_small  resq 1
font_big    resq 1
tbuf        resb 512

section .text

; void draw_text(int x /*ecx*/, int y /*edx*/, const char* s /*r8*/, COLORREF c /*r9d*/)
; - with a drop shadow, in whatever font is selected.
draw_text:
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    sub     rsp, 48
    mov     ebx, ecx
    mov     esi, edx
    mov     rdi, r8
    mov     r12d, r9d
    xor     r13d, r13d
.len:
    cmp     byte [rdi + r13], 0
    je      .draw
    inc     r13d
    jmp     .len
.draw:
    mov     rcx, [hdc_mem]
    xor     edx, edx
    call    SetTextColor
    mov     rcx, [hdc_mem]
    lea     edx, [rbx + 1]
    lea     r8d, [rsi + 1]
    mov     r9, rdi
    mov     [rsp + 32], r13
    call    TextOutA
    mov     rcx, [hdc_mem]
    mov     edx, r12d
    call    SetTextColor
    mov     rcx, [hdc_mem]
    mov     edx, ebx
    mov     r8d, esi
    mov     r9, rdi
    mov     [rsp + 32], r13
    call    TextOutA
    add     rsp, 48
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; const char* ride_suffix(int idx /*ecx*/) -> the broken-down warning or the price hint. Leaf.
ride_suffix:
    lea     rax, [broken]
    cmp     byte [rax + rcx], 0
    lea     rax, [s_price_hint]
    je      .done
    lea     rax, [s_broken]
.done:
    ret

; void use_font(HFONT f /*rcx*/)
use_font:
    sub     rsp, 40
    mov     rdx, rcx
    mov     rcx, [hdc_mem]
    call    SelectObject
    add     rsp, 40
    ret

; void draw_ui() - header, toolbar, info lines, game-over banner
draw_ui:
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 96

    PEN     C_PANEL
    xor     ecx, ecx
    xor     edx, edx
    mov     r8d, SCR_W
    mov     r9d, HEADER_H
    call    fill_rect
    PEN     C_ACCENT
    xor     ecx, ecx
    mov     edx, HEADER_H
    mov     r8d, SCR_W
    mov     r9d, 2
    call    fill_rect
    PEN     C_PANEL
    xor     ecx, ecx
    mov     edx, PANEL_Y
    mov     r8d, SCR_W
    mov     r9d, SCR_H - PANEL_Y
    call    fill_rect
    PEN     C_ACCENT
    xor     ecx, ecx
    mov     edx, PANEL_Y
    mov     r8d, SCR_W
    mov     r9d, 2
    call    fill_rect

    ; toolbar buttons
    xor     r12d, r12d
.button:
    imul    ebx, r12d, BTN_STEP
    add     ebx, BTN_X0
    cmp     r12d, [tool]
    jne     .plain
    PEN     C_ACCENT
    lea     ecx, [rbx - 2]
    mov     edx, BTN_Y - 2
    mov     r8d, BTN_W + 4
    mov     r9d, BTN_H + 4
    call    fill_rect
    PEN     C_BTN_SEL
    jmp     .fill
.plain:
    PEN     C_BTN
.fill:
    mov     ecx, ebx
    mov     edx, BTN_Y
    mov     r8d, BTN_W
    mov     r9d, BTN_H
    call    fill_rect
    cmp     r12d, TOOL_HANDY_IDX
    je      .icon_handy
    cmp     r12d, TOOL_MECH_IDX
    je      .icon_mech
    cmp     r12d, TOOL_DEMOLISH
    je      .icon_demolish
    lea     rax, [tool_icon]
    mov     eax, [rax + r12*4]
    mov     [pen], eax
    lea     ecx, [rbx + 16]
    mov     edx, BTN_Y + 15
    mov     r8d, 12
    call    diamond
    cmp     r12d, TOOL_RAISE_IDX
    je      .icon_arrow
    cmp     r12d, TOOL_LOWER_IDX
    jne     .next_button
.icon_arrow:                        ; white arrow: up for raise, down for lower
    PEN     0xFFFFFF
    lea     ecx, [rbx + 16]
    mov     edx, BTN_Y + 8
    mov     r8d, BTN_Y + 32
    call    vspan
    mov     r13d, BTN_Y + 8         ; arrow tip and which way the head points
    mov     r14d, 5
    cmp     r12d, TOOL_RAISE_IDX
    je      .arrow_head
    mov     r13d, BTN_Y + 31
    mov     r14d, -5
.arrow_head:
    lea     ecx, [rbx + 11]
    lea     edx, [r13 + r14]
    lea     r8d, [rbx + 16]
    mov     r9d, r13d
    call    line
    lea     ecx, [rbx + 21]
    lea     edx, [r13 + r14]
    lea     r8d, [rbx + 16]
    mov     r9d, r13d
    call    line
    jmp     .next_button
.icon_handy:
    mov     r8d, HANDY_SHIRT
    jmp     .icon_person
.icon_mech:
    mov     r8d, MECH_SHIRT
.icon_person:
    lea     ecx, [rbx + 16]
    mov     edx, BTN_Y + 34
    call    draw_person
    jmp     .next_button
.icon_demolish:
    PEN     0xFF5252
    xor     r13d, r13d
.cross:
    lea     ecx, [rbx + r13 + 8]
    mov     edx, BTN_Y + 12
    lea     r8d, [rbx + r13 + 22]
    mov     r9d, BTN_Y + 32
    call    line
    lea     ecx, [rbx + r13 + 22]
    mov     edx, BTN_Y + 12
    lea     r8d, [rbx + r13 + 8]
    mov     r9d, BTN_Y + 32
    call    line
    inc     r13d
    cmp     r13d, 2
    jb      .cross
.next_button:
    inc     r12d
    cmp     r12d, TOOL_COUNT
    jb      .button

    mov     eax, [game_over]
    test    eax, eax
    jz      .text
    PEN     C_ACCENT
    mov     ecx, BANNER_X - 2
    mov     edx, BANNER_Y - 2
    mov     r8d, 604
    mov     r9d, 94
    call    fill_rect
    mov     eax, [game_over]
    lea     rcx, [go_colour]
    mov     eax, [rcx + rax*4]
    mov     [pen], eax
    mov     ecx, BANNER_X
    mov     edx, BANNER_Y
    mov     r8d, 600
    mov     r9d, 90
    call    fill_rect

.text:
    call    GdiFlush                ; our pixels must land before GDI draws over them
    mov     rcx, [font_title]
    call    use_font
    mov     ecx, 12
    mov     edx, 8
    lea     r8, [s_title]
    mov     r9d, TXT_YELLOW
    call    draw_text

    mov     rcx, [font_norm]
    call    use_font
    lea     rcx, [tbuf]
    lea     rdx, [f_header]
    mov     r8d, [day]
    mov     r9d, GOAL_DAY
    mov     eax, [cash]
    mov     [rsp + 32], rax
    mov     eax, [guest_count]
    mov     [rsp + 40], rax
    mov     qword [rsp + 48], GOAL_GUESTS
    mov     eax, [handy_n]
    add     eax, [mech_n]
    mov     [rsp + 56], rax
    mov     eax, [rating]
    mov     [rsp + 64], rax
    mov     eax, [coaster_n]
    mov     [rsp + 72], rax
    call    sprintf
    mov     ecx, 272
    mov     edx, 9
    lea     r8, [tbuf]
    mov     r9d, TXT_WHITE
    call    draw_text
    cmp     dword [paused], 0
    je      .labels
    mov     rcx, [font_title]
    call    use_font
    mov     ecx, SCR_W - 190        ; left of the options button
    mov     edx, 8
    lea     r8, [s_paused]
    mov     r9d, TXT_RED
    call    draw_text

.labels:
    mov     rcx, [font_small]
    call    use_font
    xor     r12d, r12d
.label:
    imul    ebx, r12d, BTN_STEP
    add     ebx, BTN_X0
    lea     ecx, [rbx + BTN_TEXT]
    mov     edx, BTN_Y + 5
    lea     rax, [tool_name]
    mov     r8, [rax + r12*8]
    mov     r9d, TXT_WHITE
    call    draw_text
    lea     ecx, [rbx + BTN_TEXT]
    mov     edx, BTN_Y + 23
    lea     rax, [tool_price]
    mov     r8, [rax + r12*8]
    mov     r9d, TXT_GREY
    call    draw_text
    inc     r12d
    cmp     r12d, TOOL_COUNT
    jb      .label

    ; what's under the cursor
    mov     rcx, [font_norm]
    call    use_font
    imul    ebx, dword [cur_y], MAP_W
    add     ebx, [cur_x]
    lea     rcx, [map]
    movzx   r14d, byte [rcx + rbx]
    lea     rcx, [height]
    movzx   eax, byte [rcx + rbx]
    mov     [rsp + 32], rax
    lea     rax, [tile_name]
    mov     rax, [rax + r14*8]
    cmp     r14d, T_GRASS           ; grass below sea level is a lake
    jne     .named
    cmp     dword [rsp + 32], SEA_LEVEL
    jae     .named
    lea     rax, [n_water]
.named:
    mov     [rsp + 40], rax
    lea     rcx, [tbuf]
    lea     rdx, [f_cursor]
    mov     r8d, [cur_x]
    mov     r9d, [cur_y]
    call    sprintf
    cdqe
    lea     r15, [tbuf]
    add     r15, rax                ; append point
    cmp     r14d, T_STATION
    je      .coaster_info
    cmp     r14d, T_TRACK
    je      .coaster_info
    cmp     r14d, T_FERRIS
    jb      .info_done
    cmp     r14d, T_FOOD
    ja      .info_done
    lea     rax, [tile_upkeep]
    mov     eax, [rax + r14*4]
    mov     [rsp + 32], rax
    mov     ecx, ebx
    call    ride_suffix
    mov     [rsp + 40], rax
    mov     ecx, ebx
    call    ride_value
    mov     r9d, eax
    lea     rax, [price]
    movzx   r8d, byte [rax + rbx]
    mov     rcx, r15
    lea     rdx, [f_rideinfo]
    call    sprintf
    jmp     .info_done
.coaster_info:
    lea     rax, [coaster_of]
    movzx   eax, byte [rax + rbx]
    test    eax, eax
    jnz     .coaster_stats
    lea     rdx, [s_no_loop]
    cmp     r14d, T_STATION
    je      .coaster_note
    lea     rdx, [s_loose]
.coaster_note:
    mov     rcx, r15
    call    sprintf
    jmp     .info_done
.coaster_stats:
    dec     eax
    imul    eax, eax, CO_SIZE
    lea     rbx, [coasters]
    add     rbx, rax
    mov     eax, [rbx + CO_DROPS]
    mov     [rsp + 32], rax
    mov     eax, [rbx + CO_SPLASH]
    mov     [rsp + 40], rax
    mov     eax, [rbx + CO_EXCITE]
    mov     [rsp + 48], rax
    mov     eax, [rbx + CO_TICKET]
    mov     [rsp + 64], rax
    mov     ecx, [rbx + CO_STATION] ; the price and any breakdown belong to the station
    lea     rax, [price]
    movzx   eax, byte [rax + rcx]
    mov     [rsp + 56], rax
    call    ride_suffix
    mov     [rsp + 72], rax
    mov     rcx, r15
    lea     rdx, [f_coaster]
    mov     r8d, [rbx + CO_LEN]
    mov     r9d, [rbx + CO_TURNS]
    call    sprintf
.info_done:
    mov     ecx, 12
    mov     edx, LINE1_Y
    lea     r8, [tbuf]
    mov     r9d, TXT_GREY
    call    draw_text

    mov     ecx, 12
    mov     edx, LINE2_Y
    lea     r8, [msg_buf]
    mov     r9d, TXT_CYAN
    call    draw_text

    mov     rcx, [font_small]
    call    use_font
    lea     rcx, [tbuf]
    lea     rdx, [f_help]
    lea     r8, [s_off]
    cmp     dword [drag], 0
    je      .help
    lea     r8, [s_on]
.help:
    lea     r9, [s_off]
    cmp     dword [sound_on], 0
    je      .help_sound
    lea     r9, [s_on]
.help_sound:
    call    sprintf
    mov     ecx, 12
    mov     edx, LINE3_Y
    lea     r8, [tbuf]
    mov     r9d, TXT_DIM
    call    draw_text

    mov     eax, [game_over]
    test    eax, eax
    jz      .done
    mov     rcx, [font_big]
    call    use_font
    mov     eax, [game_over]
    lea     rcx, [go_title]
    mov     r8, [rcx + rax*8]
    mov     ecx, BANNER_X + 24
    mov     edx, BANNER_Y + 10
    mov     r9d, TXT_WHITE
    call    draw_text
    mov     rcx, [font_norm]
    call    use_font
    mov     eax, [game_over]
    lea     rcx, [go_sub]
    mov     r8, [rcx + rax*8]
    mov     ecx, BANNER_X + 26
    mov     edx, BANNER_Y + 58
    mov     r9d, TXT_WHITE
    call    draw_text

.done:
    add     rsp, 96
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; void render() - one whole frame into the DIB
render:
    sub     rsp, 40
    call    GdiFlush                ; last frame's text must be done before we touch pixels
    PEN     C_BG
    xor     ecx, ecx
    xor     edx, edx
    mov     r8d, SCR_W
    mov     r9d, SCR_H
    call    fill_rect
    call    draw_world
    call    draw_ui
    call    draw_options
    add     rsp, 40
    ret

; HFONT make_font(int height /*ecx*/, int weight /*edx*/)
make_font:
    sub     rsp, 120
    mov     eax, edx
    mov     [rsp + 32], rax         ; weight
    xor     eax, eax
    mov     [rsp + 40], rax         ; italic
    mov     [rsp + 48], rax         ; underline
    mov     [rsp + 56], rax         ; strikeout
    mov     [rsp + 64], rax         ; charset
    mov     [rsp + 72], rax         ; out precision
    mov     [rsp + 80], rax         ; clip precision
    mov     qword [rsp + 88], 5     ; CLEARTYPE_QUALITY
    mov     [rsp + 96], rax         ; pitch and family
    lea     rax, [font_face]
    mov     [rsp + 104], rax
    xor     edx, edx
    xor     r8d, r8d
    xor     r9d, r9d
    call    CreateFontA
    add     rsp, 120
    ret
