; options.asm - the options screen (sound volume, game speed, grid lines), opened
; with the header button or O. Settings are kept in options.cfg between sessions.

%include "defs.inc"

global draw_options, grid, load_options, options_click, options_open, tick_ms, toggle_options
global volume
extern draw_text, fclose, fill_rect, font_norm, font_small, font_title, fopen, fread, fwrite
extern GdiFlush, pen, play_sound, reload_sounds, sprintf, use_font

OPT_W             equ 440
OPT_H             equ 250
OPT_X             equ (SCR_W - OPT_W) / 2
OPT_Y             equ 170
CTRL_X            equ OPT_X + 160       ; where each row's controls start
ROW1              equ OPT_Y + 64
ROW2              equ OPT_Y + 114
ROW3              equ OPT_Y + 164
SMALL_BTN         equ 28
BAR_X             equ CTRL_X + SMALL_BTN + 8
BAR_W             equ 180
PLUS_X            equ BAR_X + BAR_W + 8
CHOICE_W          equ 80
CHOICE_STEP       equ 88
CLOSE_W           equ 90
CLOSE_H           equ 30
CLOSE_X           equ OPT_X + OPT_W - CLOSE_W - 20
CLOSE_Y           equ OPT_Y + OPT_H - CLOSE_H - 16
HDR_BTN_W         equ 100
HDR_BTN_H         equ 24
HDR_BTN_X         equ SCR_W - HDR_BTN_W - 8
HDR_BTN_Y         equ 5
VOLUME_STEP       equ 10
OPT_MAGIC         equ 'OPT1'

section .rdata
opt_file    db "options.cfg", 0
opt_mode_write  db "wb", 0
opt_mode_read   db "rb", 0
speed_ms    dd 160, 100, 55             ; tick length for slow, normal, fast
speed_names dq s_slow, s_normal, s_fast
grid_names  dq s_grid_on, s_grid_off
s_opt_title     db "Options", 0
s_hdr_btn   db "Options (O)", 0
f_volume    db "Sound volume  %d%%", 0
s_speed     db "Game speed", 0
s_grid      db "Grid lines", 0
s_minus     db "-", 0
s_plus      db "+", 0
s_slow      db "Slow", 0
s_normal    db "Normal", 0
s_fast      db "Fast", 0
s_grid_on        db "On", 0
s_grid_off       db "Off", 0
s_close     db "Close", 0
s_hint      db "O or Esc to close", 0

section .data
; the settings, saved to options.cfg in this order
settings:
volume      dd 30                       ; master sound volume, 0-100
speed       dd 1                        ; 0 slow, 1 normal, 2 fast
grid        dd 1                        ; draw grid lines between tiles
SETTINGS_SIZE equ $ - settings
tick_ms     dd 100                      ; follows speed
options_open dd 0

section .bss
alignb 16
opt_buf     resb 4 + SETTINGS_SIZE + 4  ; room to spot a file that's too long
text_buf    resb 64
btn_sel     resd 1                      ; draw the next button highlighted

section .text

; void apply_speed() - tick_ms from speed. Leaf.
apply_speed:
    mov     eax, [speed]
    lea     rcx, [speed_ms]
    mov     eax, [rcx + rax*4]
    mov     [tick_ms], eax
    ret

; void load_options() - read options.cfg if there is a valid one; keep the defaults otherwise
load_options:
    push    rbx
    push    rsi
    sub     rsp, 40
    lea     rcx, [opt_file]
    lea     rdx, [opt_mode_read]
    call    fopen
    test    rax, rax
    jz      .done
    mov     rbx, rax
    lea     rcx, [opt_buf]
    mov     edx, 1
    mov     r8d, 4 + SETTINGS_SIZE + 4
    mov     r9, rbx
    call    fread
    mov     rsi, rax
    mov     rcx, rbx
    call    fclose
    cmp     rsi, 4 + SETTINGS_SIZE
    jne     .done
    lea     rcx, [opt_buf]
    cmp     dword [rcx], OPT_MAGIC
    jne     .done
    mov     eax, [rcx + 4]          ; take each value only if it's in range
    cmp     eax, 100
    ja      .speed
    mov     [volume], eax
.speed:
    mov     eax, [rcx + 8]
    cmp     eax, 2
    ja      .grid
    mov     [speed], eax
.grid:
    mov     eax, [rcx + 12]
    cmp     eax, 1
    ja      .done
    mov     [grid], eax
.done:
    call    apply_speed
    add     rsp, 40
    pop     rsi
    pop     rbx
    ret

; void save_options()
save_options:
    push    rbx
    sub     rsp, 32
    lea     rcx, [opt_buf]
    mov     dword [rcx], OPT_MAGIC
    mov     eax, [volume]
    mov     [rcx + 4], eax
    mov     eax, [speed]
    mov     [rcx + 8], eax
    mov     eax, [grid]
    mov     [rcx + 12], eax
    lea     rcx, [opt_file]
    lea     rdx, [opt_mode_write]
    call    fopen
    test    rax, rax
    jz      .done                   ; not being able to save settings isn't worth a fuss
    mov     rbx, rax
    lea     rcx, [opt_buf]
    mov     edx, 1
    mov     r8d, 4 + SETTINGS_SIZE
    mov     r9, rbx
    call    fwrite
    mov     rcx, rbx
    call    fclose
.done:
    add     rsp, 32
    pop     rbx
    ret

; void toggle_options() - open or close the screen; closing saves the settings
toggle_options:
    sub     rsp, 40
    xor     dword [options_open], 1
    jnz     .done
    call    save_options
.done:
    add     rsp, 40
    ret

; void set_volume(int volume /*ecx*/) - clamp, resynthesise, and play a sample at the new level
set_volume:
    sub     rsp, 40
    test    ecx, ecx
    jns     .not_negative
    xor     ecx, ecx
.not_negative:
    cmp     ecx, 100
    jbe     .in_range
    mov     ecx, 100
.in_range:
    mov     [volume], ecx
    call    reload_sounds
    mov     ecx, SND_CASH
    mov     edx, SND_NOW
    call    play_sound
    add     rsp, 40
    ret

; int in_rect(int x /*ecx*/, int y /*edx*/, int w /*r8d*/, int h /*r9d*/) - is the click
; point (ebx, esi) inside? Leaf; clobbers eax.
in_rect:
    xor     eax, eax
    cmp     ebx, ecx
    jl      .out
    cmp     esi, edx
    jl      .out
    add     ecx, r8d
    cmp     ebx, ecx
    jge     .out
    add     edx, r9d
    cmp     esi, edx
    jge     .out
    inc     eax
.out:
    ret

; int options_click(int px /*ecx*/, int py /*edx*/) -> 1 if the click was the options
; screen's (the header button always is; everything is while the screen is open)
options_click:
    push    rbx
    push    rsi
    push    rdi
    sub     rsp, 32
    mov     ebx, ecx
    mov     esi, edx

    mov     ecx, HDR_BTN_X
    mov     edx, HDR_BTN_Y
    mov     r8d, HDR_BTN_W
    mov     r9d, HDR_BTN_H
    call    in_rect
    test    eax, eax
    jz      .screen
    call    toggle_options
    jmp     .mine
.screen:
    cmp     dword [options_open], 0
    je      .not_mine

    mov     ecx, CTRL_X             ; volume -
    mov     edx, ROW1 - 4
    mov     r8d, SMALL_BTN
    mov     r9d, 24
    call    in_rect
    test    eax, eax
    jz      .plus
    mov     ecx, [volume]
    sub     ecx, VOLUME_STEP
    call    set_volume
    jmp     .mine
.plus:
    mov     ecx, PLUS_X             ; volume +
    mov     edx, ROW1 - 4
    mov     r8d, SMALL_BTN
    mov     r9d, 24
    call    in_rect
    test    eax, eax
    jz      .bar
    mov     ecx, [volume]
    add     ecx, VOLUME_STEP
    call    set_volume
    jmp     .mine
.bar:
    mov     ecx, BAR_X              ; click on the bar: jump to that level, to the nearest 5%
    mov     edx, ROW1 - 4
    mov     r8d, BAR_W
    mov     r9d, 24
    call    in_rect
    test    eax, eax
    jz      .speeds
    mov     eax, ebx
    sub     eax, BAR_X
    imul    eax, eax, 20
    add     eax, BAR_W / 2
    xor     edx, edx
    mov     ecx, BAR_W
    div     ecx
    imul    ecx, eax, 5
    call    set_volume
    jmp     .mine

.speeds:
    xor     edi, edi
.speed_choice:
    imul    ecx, edi, CHOICE_STEP
    add     ecx, CTRL_X
    mov     edx, ROW2 - 4
    mov     r8d, CHOICE_W
    mov     r9d, 26
    call    in_rect
    test    eax, eax
    jz      .next_speed
    mov     [speed], edi
    call    apply_speed
    jmp     .mine
.next_speed:
    inc     edi
    cmp     edi, 3
    jb      .speed_choice

    xor     edi, edi                ; grid: On is choice 0, Off is choice 1
.grid_choice:
    imul    ecx, edi, CHOICE_STEP
    add     ecx, CTRL_X
    mov     edx, ROW3 - 4
    mov     r8d, CHOICE_W
    mov     r9d, 26
    call    in_rect
    test    eax, eax
    jz      .next_grid
    mov     eax, 1
    sub     eax, edi
    mov     [grid], eax
    jmp     .mine
.next_grid:
    inc     edi
    cmp     edi, 2
    jb      .grid_choice

    mov     ecx, CLOSE_X
    mov     edx, CLOSE_Y
    mov     r8d, CLOSE_W
    mov     r9d, CLOSE_H
    call    in_rect
    test    eax, eax
    jz      .mine
    call    toggle_options
.mine:
    mov     eax, 1
    jmp     .done
.not_mine:
    xor     eax, eax
.done:
    add     rsp, 32
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; void button(int x /*ecx*/, int y /*edx*/, int w /*r8d*/, int h /*r9d*/) - highlighted if [btn_sel]
button:
    push    rbx
    push    rsi
    push    rdi
    push    r12
    sub     rsp, 40
    mov     ebx, ecx
    mov     esi, edx
    mov     edi, r8d
    mov     r12d, r9d
    PEN     C_BTN
    cmp     dword [btn_sel], 0
    je      .fill
    PEN     C_ACCENT
    lea     ecx, [rbx - 2]
    lea     edx, [rsi - 2]
    lea     r8d, [rdi + 4]
    lea     r9d, [r12 + 4]
    call    fill_rect
    PEN     C_BTN_SEL
.fill:
    mov     ecx, ebx
    mov     edx, esi
    mov     r8d, edi
    mov     r9d, r12d
    call    fill_rect
    add     rsp, 40
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; void draw_options() - the header button, and the screen itself when it's open.
; Drawn after the rest of the UI, so it starts by flushing GDI's text.
draw_options:
    push    rbx
    push    rsi
    push    rdi
    push    r12
    sub     rsp, 40
    call    GdiFlush

    mov     eax, [options_open]
    mov     [btn_sel], eax
    mov     ecx, HDR_BTN_X
    mov     edx, HDR_BTN_Y
    mov     r8d, HDR_BTN_W
    mov     r9d, HDR_BTN_H
    call    button
    cmp     dword [options_open], 0
    je      .text

    PEN     C_ACCENT                ; the panel
    mov     ecx, OPT_X - 2
    mov     edx, OPT_Y - 2
    mov     r8d, OPT_W + 4
    mov     r9d, OPT_H + 4
    call    fill_rect
    PEN     C_PANEL
    mov     ecx, OPT_X
    mov     edx, OPT_Y
    mov     r8d, OPT_W
    mov     r9d, OPT_H
    call    fill_rect

    mov     dword [btn_sel], 0      ; volume: - [bar] +
    mov     ecx, CTRL_X
    mov     edx, ROW1 - 4
    mov     r8d, SMALL_BTN
    mov     r9d, 24
    call    button
    mov     ecx, PLUS_X
    mov     edx, ROW1 - 4
    mov     r8d, SMALL_BTN
    mov     r9d, 24
    call    button
    PEN     C_BG
    mov     ecx, BAR_X
    mov     edx, ROW1
    mov     r8d, BAR_W
    mov     r9d, 16
    call    fill_rect
    PEN     C_ACCENT
    imul    r8d, dword [volume], BAR_W
    mov     eax, r8d
    xor     edx, edx
    mov     ecx, 100
    div     ecx
    mov     r8d, eax
    mov     ecx, BAR_X
    mov     edx, ROW1
    mov     r9d, 16
    call    fill_rect

    xor     ebx, ebx                ; speed choices
.speed_button:
    xor     eax, eax
    cmp     ebx, [speed]
    sete    al
    mov     [btn_sel], eax
    imul    ecx, ebx, CHOICE_STEP
    add     ecx, CTRL_X
    mov     edx, ROW2 - 4
    mov     r8d, CHOICE_W
    mov     r9d, 26
    call    button
    inc     ebx
    cmp     ebx, 3
    jb      .speed_button

    xor     ebx, ebx                ; grid choices
.grid_button:
    mov     eax, 1
    sub     eax, ebx
    cmp     eax, [grid]
    sete    al
    movzx   eax, al
    mov     [btn_sel], eax
    imul    ecx, ebx, CHOICE_STEP
    add     ecx, CTRL_X
    mov     edx, ROW3 - 4
    mov     r8d, CHOICE_W
    mov     r9d, 26
    call    button
    inc     ebx
    cmp     ebx, 2
    jb      .grid_button

    mov     dword [btn_sel], 0
    mov     ecx, CLOSE_X
    mov     edx, CLOSE_Y
    mov     r8d, CLOSE_W
    mov     r9d, CLOSE_H
    call    button

.text:
    call    GdiFlush
    mov     rcx, [font_small]
    call    use_font
    mov     ecx, HDR_BTN_X + 16
    mov     edx, HDR_BTN_Y + 4
    lea     r8, [s_hdr_btn]
    mov     r9d, TXT_WHITE
    call    draw_text
    cmp     dword [options_open], 0
    je      .done

    mov     rcx, [font_title]
    call    use_font
    mov     ecx, OPT_X + 20
    mov     edx, OPT_Y + 16
    lea     r8, [s_opt_title]
    mov     r9d, TXT_YELLOW
    call    draw_text

    mov     rcx, [font_norm]
    call    use_font
    lea     rcx, [text_buf]
    lea     rdx, [f_volume]
    mov     r8d, [volume]
    call    sprintf
    mov     ecx, OPT_X + 20
    mov     edx, ROW1 - 2
    lea     r8, [text_buf]
    mov     r9d, TXT_WHITE
    call    draw_text
    mov     ecx, CTRL_X + 11
    mov     edx, ROW1 - 3
    lea     r8, [s_minus]
    mov     r9d, TXT_WHITE
    call    draw_text
    mov     ecx, PLUS_X + 9
    mov     edx, ROW1 - 3
    lea     r8, [s_plus]
    mov     r9d, TXT_WHITE
    call    draw_text

    mov     ecx, OPT_X + 20
    mov     edx, ROW2
    lea     r8, [s_speed]
    mov     r9d, TXT_WHITE
    call    draw_text
    xor     ebx, ebx
.speed_label:
    imul    ecx, ebx, CHOICE_STEP
    add     ecx, CTRL_X + 14
    mov     edx, ROW2
    lea     rax, [speed_names]
    mov     r8, [rax + rbx*8]
    mov     r9d, TXT_WHITE
    call    draw_text
    inc     ebx
    cmp     ebx, 3
    jb      .speed_label

    mov     ecx, OPT_X + 20
    mov     edx, ROW3
    lea     r8, [s_grid]
    mov     r9d, TXT_WHITE
    call    draw_text
    xor     ebx, ebx
.grid_label:
    imul    ecx, ebx, CHOICE_STEP
    add     ecx, CTRL_X + 14
    mov     edx, ROW3
    lea     rax, [grid_names]
    mov     r8, [rax + rbx*8]
    mov     r9d, TXT_WHITE
    call    draw_text
    inc     ebx
    cmp     ebx, 2
    jb      .grid_label

    mov     ecx, CLOSE_X + 26
    mov     edx, CLOSE_Y + 6
    lea     r8, [s_close]
    mov     r9d, TXT_WHITE
    call    draw_text
    mov     rcx, [font_small]
    call    use_font
    mov     ecx, OPT_X + 20
    mov     edx, CLOSE_Y + 8
    lea     r8, [s_hint]
    mov     r9d, TXT_DIM
    call    draw_text

.done:
    add     rsp, 40
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret
