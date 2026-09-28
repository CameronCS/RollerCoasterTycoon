; save.asm - saving the park to park.sav and loading it back (F5 / F9).
;
; The file is a 12-byte header (magic, version, body size) followed by every
; block listed in save_blocks, back to back. Coaster circuits and park stats
; aren't saved: they're rebuilt from the map after loading. A load reads and
; checks the whole file before touching the game, so a bad file changes nothing.

%include "defs.inc"

global load_game, save_game
extern analyze_coasters, cash, compute_stats, cur_x, cur_y, day, fclose, fopen, fread, fwrite
extern game_over, guests, handy_n, handymen, height, map, next_id, post_msg, rng, swept, tick
extern tool, visitors

SAVE_MAGIC        equ 'RCTA'
SAVE_VERSION      equ 1
SAVE_HEADER       equ 12
SAVE_BUF_SIZE     equ 8192              ; comfortably more than header + body

section .rdata
save_name   db "park.sav", 0
mode_write  db "wb", 0
mode_read   db "rb", 0

m_saved     db `Park saved to park.sav.`, 0
m_save_fail db `Couldn't write park.sav.`, 0
m_loaded    db `Park loaded from park.sav.`, 0
m_no_save   db `No saved park yet - press F5 to save one.`, 0
m_bad_save  db `park.sav is damaged or from a different version of the game.`, 0

section .data
; everything that goes in the file, as (address, size) pairs
save_blocks dq rng, 4, cash, 4, day, 4, tick, 4, cur_x, 4, cur_y, 4, tool, 4
            dq game_over, 4, next_id, 4, visitors, 4, handy_n, 4, swept, 4
            dq map, MAP_SIZE, height, MAP_SIZE
            dq handymen, MAX_HANDY * HANDY_SIZE, guests, MAX_GUESTS * GUEST_SIZE
SAVE_BLOCKS equ ($ - save_blocks) / 16

section .bss
alignb 16
save_buf    resb SAVE_BUF_SIZE

section .text

; int body_size() -> total bytes of all save blocks. Leaf.
body_size:
    lea     rdx, [save_blocks]
    mov     ecx, SAVE_BLOCKS
    xor     eax, eax
.block:
    add     eax, [rdx + 8]
    add     rdx, 16
    dec     ecx
    jnz     .block
    ret

; void copy_blocks(int unpack /*ecx*/) - game state -> save_buf body, or back. Leaf.
copy_blocks:
    push    rbx
    push    rsi
    push    rdi
    lea     rbx, [save_blocks]
    lea     r8, [save_buf + SAVE_HEADER]
    mov     r9d, SAVE_BLOCKS
    mov     r10d, ecx
.block:
    mov     rax, [rbx]              ; the state's address
    mov     rcx, [rbx + 8]          ; its size
    mov     rsi, rax
    mov     rdi, r8
    test    r10d, r10d
    jz      .copy
    mov     rsi, r8
    mov     rdi, rax
.copy:
    add     r8, rcx
    rep     movsb
    add     rbx, 16
    dec     r9d
    jnz     .block
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; void save_game()
save_game:
    push    rbx
    push    rsi
    sub     rsp, 40

    xor     ecx, ecx
    call    copy_blocks
    call    body_size
    lea     rbx, [save_buf]
    mov     dword [rbx], SAVE_MAGIC
    mov     dword [rbx + 4], SAVE_VERSION
    mov     [rbx + 8], eax
    lea     esi, [rax + SAVE_HEADER] ; bytes to write

    lea     rcx, [save_name]
    lea     rdx, [mode_write]
    call    fopen
    test    rax, rax
    jz      .failed
    mov     rbx, rax
    lea     rcx, [save_buf]
    mov     edx, 1
    mov     r8d, esi
    mov     r9, rbx
    call    fwrite
    mov     [rsp + 32], rax
    mov     rcx, rbx
    call    fclose
    test    eax, eax                ; fclose flushes, so it can fail too
    jnz     .failed
    cmp     [rsp + 32], rsi
    jne     .failed
    lea     rcx, [m_saved]
    jmp     .report
.failed:
    lea     rcx, [m_save_fail]
.report:
    call    post_msg
    add     rsp, 40
    pop     rsi
    pop     rbx
    ret

; void load_game()
load_game:
    push    rbx
    push    rsi
    sub     rsp, 40

    lea     rcx, [save_name]
    lea     rdx, [mode_read]
    call    fopen
    test    rax, rax
    jz      .missing
    mov     rbx, rax
    lea     rcx, [save_buf]
    mov     edx, 1
    mov     r8d, SAVE_BUF_SIZE
    mov     r9, rbx
    call    fread
    mov     rsi, rax                ; bytes actually read
    mov     rcx, rbx
    call    fclose

    ; the file must be exactly header + body, with our magic and version
    call    body_size
    lea     ebx, [rax + SAVE_HEADER]
    cmp     rsi, rbx
    jne     .bad
    lea     rcx, [save_buf]
    cmp     dword [rcx], SAVE_MAGIC
    jne     .bad
    cmp     dword [rcx + 4], SAVE_VERSION
    jne     .bad
    cmp     [rcx + 8], eax
    jne     .bad

    mov     ecx, 1
    call    copy_blocks
    call    analyze_coasters        ; circuits and stats come from the map
    call    compute_stats
    lea     rcx, [m_loaded]
    jmp     .report
.missing:
    lea     rcx, [m_no_save]
    jmp     .report
.bad:
    lea     rcx, [m_bad_save]
.report:
    call    post_msg
    add     rsp, 40
    pop     rsi
    pop     rbx
    ret
