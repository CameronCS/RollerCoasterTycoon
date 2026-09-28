; input.asm - keyboard and mouse handling.

%include "defs.inc"

global ldrag, on_key, on_mouse_down, on_mouse_move, on_wheel, rdrag
extern build, change_price, cur_x, cur_y, demolish_here, drag, game_over, init_game, load_game
extern options_click, options_open, paused, pick_tile, running, save_game, toggle_options
extern toggle_sound, tool

VK_F5             equ 0x74
VK_F9             equ 0x78
VK_ADD            equ 0x6B              ; numpad +
VK_SUBTRACT       equ 0x6D              ; numpad -
VK_OEM_PLUS       equ 0xBB              ; =/+ key
VK_OEM_MINUS      equ 0xBD

section .bss
alignb 16
ldrag       resd 1
rdrag       resd 1

section .text

; void on_key(int vk /*ecx*/)
on_key:
    push    rbx
    sub     rsp, 32
    mov     ebx, ecx
    cmp     ebx, 'O'
    je      .options
    cmp     dword [options_open], 0
    je      .game_keys
    cmp     ebx, 0x1B               ; with the options screen up, Esc just closes it
    jne     .done
.options:
    call    toggle_options
    jmp     .done
.game_keys:
    cmp     ebx, 0x1B               ; Esc
    je      .quit
    cmp     ebx, 'Q'
    je      .quit
    cmp     ebx, VK_F5
    je      .save
    cmp     ebx, VK_F9              ; loading works even after the scenario ends
    je      .load
    cmp     ebx, 'N'
    je      .sound
    cmp     dword [game_over], GO_NONE
    je      .playing
    cmp     ebx, 'R'
    jne     .done
    call    init_game
    jmp     .done

.playing:
    cmp     ebx, 'W'
    je      .up
    cmp     ebx, 0x26
    je      .up
    cmp     ebx, 'S'
    je      .down
    cmp     ebx, 0x28
    je      .down
    cmp     ebx, 'A'
    je      .left
    cmp     ebx, 0x25
    je      .left
    cmp     ebx, 'D'
    je      .right
    cmp     ebx, 0x27
    je      .right
    cmp     ebx, 'P'
    je      .pause
    cmp     ebx, 'B'
    je      .drag
    cmp     ebx, ' '
    je      .build
    cmp     ebx, 0x0D
    je      .build
    cmp     ebx, '0'
    je      .key_handy
    cmp     ebx, 'M'
    je      .key_mech
    cmp     ebx, VK_ADD
    je      .price_up
    cmp     ebx, VK_OEM_PLUS
    je      .price_up
    cmp     ebx, VK_SUBTRACT
    je      .price_down
    cmp     ebx, VK_OEM_MINUS
    je      .price_down
    cmp     ebx, 'X'
    je      .key_demolish
    cmp     ebx, '1'
    jb      .done
    cmp     ebx, '9'
    ja      .done
    sub     ebx, '1'
    mov     [tool], ebx
    jmp     .done
.key_handy:
    mov     dword [tool], TOOL_HANDY_IDX
    jmp     .done
.key_mech:
    mov     dword [tool], TOOL_MECH_IDX
    jmp     .done
.key_demolish:
    mov     dword [tool], TOOL_DEMOLISH
    jmp     .done
.price_up:
    mov     ecx, 1
    call    change_price
    jmp     .done
.price_down:
    mov     ecx, -1
    call    change_price
    jmp     .done
.sound:
    call    toggle_sound
    jmp     .done

.up:
    cmp     dword [cur_y], 0
    je      .done
    dec     dword [cur_y]
    jmp     .moved
.down:
    cmp     dword [cur_y], MAP_H - 1
    je      .done
    inc     dword [cur_y]
    jmp     .moved
.left:
    cmp     dword [cur_x], 0
    je      .done
    dec     dword [cur_x]
    jmp     .moved
.right:
    cmp     dword [cur_x], MAP_W - 1
    je      .done
    inc     dword [cur_x]
.moved:
    cmp     dword [drag], 0
    je      .done
.build:
    call    build
    jmp     .done
.drag:
    xor     dword [drag], 1
    jmp     .done
.pause:
    xor     dword [paused], 1
    jmp     .done
.save:
    call    save_game
    jmp     .done
.load:
    call    load_game
    jmp     .done
.quit:
    mov     dword [running], 0
.done:
    add     rsp, 32
    pop     rbx
    ret

; void on_mouse_move(int px /*ecx*/, int py /*edx*/, int buttons /*r8d*/)
on_mouse_move:
    push    rbx
    sub     rsp, 32
    mov     ebx, r8d
    call    pick_tile
    cmp     eax, -1
    je      .done
    cmp     eax, [cur_x]
    jne     .moved
    cmp     edx, [cur_y]
    je      .done
.moved:
    mov     [cur_x], eax
    mov     [cur_y], edx
    cmp     dword [game_over], GO_NONE
    jne     .done
    test    ebx, MK_LBUTTON
    jz      .right
    cmp     dword [ldrag], 0
    je      .right
    call    build
    jmp     .done
.right:
    test    ebx, MK_RBUTTON
    jz      .done
    cmp     dword [rdrag], 0
    je      .done
    call    demolish_here
.done:
    add     rsp, 32
    pop     rbx
    ret

; void on_mouse_down(int px /*ecx*/, int py /*edx*/, int right /*r8d*/)
on_mouse_down:
    push    rbx
    push    rsi
    push    rdi
    sub     rsp, 32
    mov     ebx, ecx
    mov     esi, edx
    mov     edi, r8d
    call    options_click           ; the options button and screen come first
    test    eax, eax
    jnz     .done
    cmp     esi, PANEL_Y
    jl      .map
    test    edi, edi
    jnz     .done
    mov     eax, esi                ; toolbar button?
    sub     eax, BTN_Y
    cmp     eax, BTN_H
    jae     .done
    mov     eax, ebx
    sub     eax, BTN_X0
    js      .done
    xor     edx, edx
    mov     ecx, BTN_STEP
    div     ecx
    cmp     eax, TOOL_COUNT
    jae     .done
    cmp     edx, BTN_W
    jae     .done
    mov     [tool], eax
    jmp     .done
.map:
    mov     ecx, ebx
    mov     edx, esi
    call    pick_tile
    cmp     eax, -1
    je      .done
    mov     [cur_x], eax
    mov     [cur_y], edx
    cmp     dword [game_over], GO_NONE
    jne     .done
    test    edi, edi
    jnz     .right
    mov     dword [ldrag], 1
    call    build
    jmp     .done
.right:
    mov     dword [rdrag], 1
    call    demolish_here
.done:
    add     rsp, 32
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; void on_wheel(int delta /*ecx*/) - the scroll wheel changes the price of the ride under the cursor
on_wheel:
    sub     rsp, 40
    cmp     dword [game_over], GO_NONE
    jne     .done
    cmp     dword [options_open], 0
    jne     .done
    mov     eax, ecx
    mov     ecx, 1
    test    eax, eax
    jg      .change
    mov     ecx, -1
.change:
    call    change_price
.done:
    add     rsp, 40
    ret
