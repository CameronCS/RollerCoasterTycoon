; main.asm - a tiny RollerCoaster Tycoon tribute, written (like the original) in assembly.
; x86-64, Intel syntax (NASM), Windows x64 calling convention, Win32 + GDI + the C runtime.
; This module owns the window, the message loop and startup; build.bat assembles every
; module in src/ and links them into tycoon.exe.
;
; Modules:
;   defs.inc      constants, record layouts, macros
;   world.asm     shared game state, tile tables, rand / tile lookups / news ticker
;   park.asm      new game, terrain, building and landscaping
;   sim.asm       guests, handymen, admissions, days
;   coaster.asm   coaster circuit tracing and ratings
;   raster.asm    pixel primitives
;   park_draw.asm isometric drawing and mouse picking
;   ui.asm        header, toolbar, text, frame composition
;   input.asm     keyboard and mouse
;
; Controls: left-click/drag builds with the current tool, right-click/drag demolishes,
;           click a toolbar button or press 1-9, 0 or X to pick a tool. Keyboard also
;           works: arrows/WASD move the cursor, Space/Enter builds, B toggles
;           drag-build, P pauses, R restarts after the scenario ends, Esc/Q quits.
;
; The land has heights 0-5. Raise and lower it to make hills; land dug below sea
; level fills with water. Guests can only climb one level per step, but coaster
; track follows the terrain - so hills give it drops, and it can splash over lakes.
;
; Guests enter at the park entrance, wander the paths, and ride any attraction
; next to the path tile they're standing on. They pay for tickets, get hungry,
; get queasy on coasters (and throw up on your paths), and go home when
; they're broke or miserable. Get enough guests into the park before the deadline.
;
; Roller coasters are built from a station plus track tiles. A coaster opens
; once its track leaves the station and loops back into it; the circuit's
; length and number of turns decide its excitement, ticket price and nausea.
; Handymen walk the paths and sweep up vomit, for a daily wage.
;
; Graphics: everything in the park is rasterised by hand into a 32-bit DIB section
; (spans, isometric blocks, circles, Bresenham lines); GDI only draws the text and
; copies the finished frame to the window.
;

%include "defs.inc"

global hdc_mem, main, running
extern AdjustWindowRect, anim, BeginPaint, BitBlt, CreateCompatibleDC, CreateDIBSection
extern CreateWindowExA, DefWindowProcA, DispatchMessageA, EndPaint, font_big, font_norm, font_small
extern font_title, frac, game_over, GetDC, GetModuleHandleA, GetTickCount, init_game, ldrag
extern LoadCursorA, make_font, on_key, on_mouse_down, on_mouse_move, paused, PeekMessageA, pixels
extern PostQuitMessage, rdrag, RegisterClassExA, ReleaseCapture, ReleaseDC, render, rng
extern SelectObject, SetBkMode, SetCapture, sim_tick, Sleep, TranslateMessage

section .rdata
class_name  db "TycoonAsm", 0
win_title   db "RollerCoaster Tycoon .asm", 0

section .data
running     dd 1
bmi         dd 40, SCR_W, -SCR_H        ; BITMAPINFOHEADER: size, width, height (negative = top-down)
            dw 1, 32                    ; planes, bits per pixel
            dd 0, 0, 0, 0, 0, 0         ; BI_RGB, then unused fields
win_rect    dd 0, 0, SCR_W, SCR_H

section .bss
alignb 16
hinst       resq 1
hwnd        resq 1
hdc_mem     resq 1
wc          resb 80                     ; WNDCLASSEXA
msg         resb 48                     ; MSG
last_tick   resd 1

section .text

; void blit_to(HDC dc /*rcx*/) - copy the finished frame to a window DC
blit_to:
    sub     rsp, 88
    xor     edx, edx
    xor     r8d, r8d
    mov     r9d, SCR_W
    mov     qword [rsp + 32], SCR_H
    mov     rax, [hdc_mem]
    mov     [rsp + 40], rax
    mov     qword [rsp + 48], 0
    mov     qword [rsp + 56], 0
    mov     qword [rsp + 64], SRCCOPY
    call    BitBlt
    add     rsp, 88
    ret

present:
    push    rbx
    sub     rsp, 32
    mov     rcx, [hwnd]
    call    GetDC
    mov     rbx, rax
    mov     rcx, rbx
    call    blit_to
    mov     rcx, [hwnd]
    mov     rdx, rbx
    call    ReleaseDC
    add     rsp, 32
    pop     rbx
    ret

; LRESULT wndproc(HWND /*rcx*/, UINT /*edx*/, WPARAM /*r8*/, LPARAM /*r9*/)
wndproc:
    push    rbx
    push    rsi
    push    rdi
    push    r12
    sub     rsp, 120                ; PAINTSTRUCT at [rsp+40]
    mov     rbx, rcx
    mov     esi, edx
    mov     rdi, r8
    mov     r12, r9

    cmp     esi, WM_DESTROY
    je      .destroy
    cmp     esi, WM_ERASEBKGND
    je      .erase
    cmp     esi, WM_PAINT
    je      .paint
    cmp     esi, WM_KEYDOWN
    je      .key
    cmp     esi, WM_MOUSEMOVE
    je      .move
    cmp     esi, WM_LBUTTONDOWN
    je      .ldown
    cmp     esi, WM_RBUTTONDOWN
    je      .rdown
    cmp     esi, WM_LBUTTONUP
    je      .up
    cmp     esi, WM_RBUTTONUP
    je      .up
    mov     rcx, rbx
    mov     edx, esi
    mov     r8, rdi
    mov     r9, r12
    call    DefWindowProcA
    jmp     .out

.destroy:
    mov     dword [running], 0
    xor     ecx, ecx
    call    PostQuitMessage
    jmp     .zero
.erase:
    mov     eax, 1
    jmp     .out
.paint:
    mov     rcx, rbx
    lea     rdx, [rsp + 40]
    call    BeginPaint
    mov     rcx, rax
    call    blit_to
    mov     rcx, rbx
    lea     rdx, [rsp + 40]
    call    EndPaint
    jmp     .zero
.key:
    mov     ecx, edi
    call    on_key
    jmp     .zero
.move:
    movsx   ecx, r12w
    mov     edx, r12d
    shr     edx, 16
    movsx   edx, dx
    mov     r8d, edi
    call    on_mouse_move
    jmp     .zero
.ldown:
    xor     r8d, r8d
    jmp     .down
.rdown:
    mov     r8d, 1
.down:
    mov     [rsp + 32], r8d
    mov     rcx, rbx
    call    SetCapture              ; keep getting moves while dragging off the map
    movsx   ecx, r12w
    mov     edx, r12d
    shr     edx, 16
    movsx   edx, dx
    mov     r8d, [rsp + 32]
    call    on_mouse_down
    jmp     .zero
.up:
    mov     dword [ldrag], 0
    mov     dword [rdrag], 0
    call    ReleaseCapture
.zero:
    xor     eax, eax
.out:
    add     rsp, 120
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret

main:
    push    rbx
    push    rsi
    push    rdi
    sub     rsp, 112

    xor     ecx, ecx
    call    GetModuleHandleA
    mov     [hinst], rax

    lea     rbx, [wc]
    mov     dword [rbx], 80         ; cbSize
    lea     rax, [wndproc]
    mov     [rbx + 8], rax
    mov     rax, [hinst]
    mov     [rbx + 24], rax
    xor     ecx, ecx
    mov     edx, IDC_ARROW
    call    LoadCursorA
    mov     [rbx + 40], rax
    lea     rax, [class_name]
    mov     [rbx + 64], rax
    mov     rcx, rbx
    call    RegisterClassExA

    lea     rcx, [win_rect]         ; window size that gives an SCR_W x SCR_H client area
    mov     edx, WIN_STYLE
    xor     r8d, r8d
    call    AdjustWindowRect

    xor     ecx, ecx
    lea     rdx, [class_name]
    lea     r8, [win_title]
    mov     r9d, WIN_STYLE
    mov     dword [rsp + 32], CW_USEDEFAULT
    mov     dword [rsp + 40], CW_USEDEFAULT
    mov     eax, [win_rect + 8]
    sub     eax, [win_rect]
    mov     [rsp + 48], rax
    mov     eax, [win_rect + 12]
    sub     eax, [win_rect + 4]
    mov     [rsp + 56], rax
    mov     qword [rsp + 64], 0
    mov     qword [rsp + 72], 0
    mov     rax, [hinst]
    mov     [rsp + 80], rax
    mov     qword [rsp + 88], 0
    call    CreateWindowExA
    mov     [hwnd], rax

    ; off-screen frame: a 32-bit top-down DIB we write pixels into directly
    mov     rcx, [hwnd]
    call    GetDC
    mov     rsi, rax
    mov     rcx, rsi
    call    CreateCompatibleDC
    mov     [hdc_mem], rax
    mov     rcx, rsi
    lea     rdx, [bmi]
    xor     r8d, r8d
    lea     r9, [pixels]
    mov     qword [rsp + 32], 0
    mov     qword [rsp + 40], 0
    call    CreateDIBSection
    mov     rcx, [hdc_mem]
    mov     rdx, rax
    call    SelectObject
    mov     rcx, [hwnd]
    mov     rdx, rsi
    call    ReleaseDC

    mov     rcx, [hdc_mem]
    mov     edx, 1                  ; TRANSPARENT text background
    call    SetBkMode
    mov     ecx, -18
    mov     edx, 800
    call    make_font
    mov     [font_title], rax
    mov     ecx, -14
    mov     edx, 400
    call    make_font
    mov     [font_norm], rax
    mov     ecx, -13
    mov     edx, 400
    call    make_font
    mov     [font_small], rax
    mov     ecx, -34
    mov     edx, 800
    call    make_font
    mov     [font_big], rax

    call    GetTickCount
    mov     [last_tick], eax
    or      eax, 1                  ; xorshift state must be nonzero
    mov     [rng], eax
    call    init_game

.loop:
    lea     rcx, [msg]
    xor     edx, edx
    xor     r8d, r8d
    xor     r9d, r9d
    mov     qword [rsp + 32], PM_REMOVE
    call    PeekMessageA
    test    eax, eax
    jz      .pumped
    cmp     dword [msg + 8], WM_QUIT
    je      .quit
    lea     rcx, [msg]
    call    TranslateMessage
    lea     rcx, [msg]
    call    DispatchMessageA
    jmp     .loop
.pumped:
    cmp     dword [running], 0
    je      .quit

    ; run as many simulation ticks as real time says are due
    call    GetTickCount
    mov     ebx, eax
    mov     eax, ebx
    sub     eax, [last_tick]
    cmp     eax, 1000
    jb      .ticks
    mov     [last_tick], ebx        ; fell far behind (window dragged?): skip ahead
.ticks:
    mov     eax, ebx
    sub     eax, [last_tick]
    cmp     eax, TICK_MS
    jb      .frame
    add     dword [last_tick], TICK_MS
    cmp     dword [paused], 0
    jne     .ticks
    cmp     dword [game_over], GO_NONE
    jne     .ticks
    call    sim_tick
    jmp     .ticks

.frame:
    shl     eax, 8                  ; frac = time into this tick, 0-256
    xor     edx, edx
    mov     ecx, TICK_MS
    div     ecx
    cmp     dword [paused], 0
    jne     .still
    cmp     dword [game_over], GO_NONE
    je      .moving
.still:
    mov     eax, 256
    jmp     .set_frac
.moving:
    inc     dword [anim]
.set_frac:
    mov     [frac], eax
    call    render
    call    present
    mov     ecx, 15
    call    Sleep
    jmp     .loop

.quit:
    xor     eax, eax
    add     rsp, 112
    pop     rdi
    pop     rsi
    pop     rbx
    ret
