; staff.asm - handymen and mechanics. Handymen patrol the paths and sweep up any
; vomit they find; mechanics follow a walking-distance map to the nearest broken
; ride and repair it.

%include "defs.inc"

global plan_repairs, update_staff
extern broken, dir_dx, dir_dy, dir_walkable, fix_ride, height, map, neighbor, pick_dir, swept
extern tile_at

section .bss
alignb 16
repair_dist resw MAP_SIZE           ; steps from each path tile to a tile beside a broken ride
bfs_queue   resw MAP_SIZE
any_broken  resd 1

section .text

; void update_staff(Staff* s /*rcx*/)
update_staff:
    cmp     byte [rcx + H_TYPE], STAFF_MECH
    je      update_mechanic
    jmp     update_handy

; ---------------------------------------------------------------------------
; void update_handy(Handyman* h /*rcx*/) - sweep vomit underfoot, head for any
; next door, otherwise patrol the paths.
; ---------------------------------------------------------------------------
update_handy:
    push    rbx
    push    rsi
    push    r12
    push    r13
    sub     rsp, 40
    mov     rbx, rcx
    movzx   r12d, byte [rbx + H_X]
    movzx   r13d, byte [rbx + H_Y]
    mov     [rbx + H_PX], r12b
    mov     [rbx + H_PY], r13b

    cmp     byte [rbx + H_BUSY], 0
    je      .look
    dec     byte [rbx + H_BUSY]
    jmp     .done

.look:
    mov     ecx, r12d
    mov     edx, r13d
    call    tile_at
    cmp     eax, T_PUKE
    jne     .seek
    imul    eax, r13d, MAP_W
    add     eax, r12d
    lea     rcx, [map]
    mov     byte [rcx + rax], T_PATH
    mov     byte [rbx + H_BUSY], SWEEP_TICKS
    inc     dword [swept]
    jmp     .done

.seek:
    xor     esi, esi
.seek_dir:
    lea     rax, [dir_dx]
    movsx   ecx, byte [rax + rsi]
    add     ecx, r12d
    lea     rax, [dir_dy]
    movsx   edx, byte [rax + rsi]
    add     edx, r13d
    call    tile_at
    cmp     eax, T_PUKE
    je      .step
    inc     esi
    cmp     esi, 4
    jb      .seek_dir

    movzx   ecx, byte [rbx + H_DIR]
    call    pick_dir
    cmp     eax, -1
    je      .done                   ; stuck: wait to be fired
    mov     esi, eax
.step:
    mov     [rbx + H_DIR], sil
    lea     rax, [dir_dx]
    movsx   ecx, byte [rax + rsi]
    add     r12d, ecx
    lea     rax, [dir_dy]
    movsx   ecx, byte [rax + rsi]
    add     r13d, ecx
    mov     [rbx + H_X], r12b
    mov     [rbx + H_Y], r13b
.done:
    add     rsp, 40
    pop     r13
    pop     r12
    pop     rsi
    pop     rbx
    ret

; int walkable_at(int idx /*ecx*/) -> 1 on a path-like tile. Leaf; clobbers eax.
walkable_at:
    lea     rax, [map]
    movzx   eax, byte [rax + rcx]
    cmp     eax, T_PATH
    je      .yes
    cmp     eax, T_ENTRANCE
    je      .yes
    cmp     eax, T_PUKE
    je      .yes
    xor     eax, eax
    ret
.yes:
    mov     eax, 1
    ret

; ---------------------------------------------------------------------------
; void plan_repairs() - breadth-first search outwards along the paths from every
; path tile beside a broken ride, recording how many steps each tile is from one.
; Mechanics just walk downhill on this map.
; ---------------------------------------------------------------------------
plan_repairs:
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14
    sub     rsp, 40

    lea     rdi, [repair_dist]
    mov     ax, 0xFFFF
    mov     ecx, MAP_SIZE
    rep     stosw
    mov     dword [any_broken], 0
    lea     rsi, [bfs_queue]
    xor     r12d, r12d              ; queue head
    xor     r13d, r13d              ; queue tail

    xor     ebx, ebx                ; seed with the path beside every broken ride
.seed:
    lea     rax, [broken]
    cmp     byte [rax + rbx], 0
    je      .next_seed
    mov     dword [any_broken], 1
    xor     r14d, r14d
.seed_dir:
    mov     ecx, ebx
    mov     edx, r14d
    call    neighbor
    cmp     eax, -1
    je      .next_seed_dir
    mov     edi, eax
    mov     ecx, edi
    call    walkable_at
    test    eax, eax
    jz      .next_seed_dir
    lea     rax, [repair_dist]
    cmp     word [rax + rdi*2], 0
    je      .next_seed_dir          ; already seeded
    mov     word [rax + rdi*2], 0
    mov     [rsi + r13*2], di
    inc     r13d
.next_seed_dir:
    inc     r14d
    cmp     r14d, 4
    jb      .seed_dir
.next_seed:
    inc     ebx
    cmp     ebx, MAP_SIZE
    jb      .seed

.search:
    cmp     r12d, r13d
    jae     .done
    movzx   ebx, word [rsi + r12*2]
    inc     r12d
    xor     r14d, r14d
.search_dir:
    mov     ecx, ebx
    mov     edx, r14d
    call    neighbor
    cmp     eax, -1
    je      .next_search_dir
    mov     edi, eax
    lea     rax, [repair_dist]
    cmp     word [rax + rdi*2], 0xFFFF
    jne     .next_search_dir
    mov     ecx, edi
    call    walkable_at
    test    eax, eax
    jz      .next_search_dir
    lea     rax, [height]           ; the same one-level step rule people walk by
    movzx   ecx, byte [rax + rdi]
    movzx   edx, byte [rax + rbx]
    sub     ecx, edx
    inc     ecx
    cmp     ecx, 2
    ja      .next_search_dir
    lea     rax, [repair_dist]
    movzx   ecx, word [rax + rbx*2]
    inc     ecx
    mov     [rax + rdi*2], cx
    mov     [rsi + r13*2], di
    inc     r13d
.next_search_dir:
    inc     r14d
    cmp     r14d, 4
    jb      .search_dir
    jmp     .search

.done:
    add     rsp, 40
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; void update_mechanic(Staff* m /*rcx*/) - repair a broken ride next door, walk
; towards the nearest one, or patrol.
; ---------------------------------------------------------------------------
update_mechanic:
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14
    sub     rsp, 40                 ; [rsp+32] best distance so far
    mov     rbx, rcx
    movzx   r12d, byte [rbx + H_X]
    movzx   r13d, byte [rbx + H_Y]
    mov     [rbx + H_PX], r12b
    mov     [rbx + H_PY], r13b
    imul    esi, r13d, MAP_W
    add     esi, r12d               ; our map index

    cmp     byte [rbx + H_BUSY], 0
    je      .idle
    dec     byte [rbx + H_BUSY]     ; mid-repair
    jnz     .done
    movzx   ecx, word [rbx + H_TARGET]
    mov     word [rbx + H_TARGET], NO_TARGET
    cmp     ecx, NO_TARGET
    je      .done
    lea     rax, [broken]           ; still broken? (another mechanic may have beaten us)
    cmp     byte [rax + rcx], 0
    je      .done
    call    fix_ride
    jmp     .done

.idle:
    xor     edi, edi                ; a broken ride right next to us?
.beside:
    mov     ecx, esi
    mov     edx, edi
    call    neighbor
    cmp     eax, -1
    je      .next_beside
    lea     rcx, [broken]
    cmp     byte [rcx + rax], 0
    je      .next_beside
    mov     [rbx + H_TARGET], ax
    mov     byte [rbx + H_BUSY], FIX_TICKS
    jmp     .done
.next_beside:
    inc     edi
    cmp     edi, 4
    jb      .beside

    cmp     dword [any_broken], 0
    je      .patrol
    lea     rax, [repair_dist]      ; step to the neighbour closest to a broken ride
    movzx   eax, word [rax + rsi*2]
    mov     [rsp + 32], eax
    mov     r14d, -1                ; best direction
    xor     edi, edi
.toward:
    mov     ecx, edi
    call    dir_walkable
    test    eax, eax
    jz      .next_toward
    mov     ecx, esi
    mov     edx, edi
    call    neighbor
    lea     rcx, [repair_dist]
    movzx   eax, word [rcx + rax*2]
    cmp     eax, [rsp + 32]
    jae     .next_toward
    mov     [rsp + 32], eax
    mov     r14d, edi
.next_toward:
    inc     edi
    cmp     edi, 4
    jb      .toward
    mov     eax, r14d
    cmp     eax, -1
    jne     .step

.patrol:
    movzx   ecx, byte [rbx + H_DIR]
    call    pick_dir
    cmp     eax, -1
    je      .done                   ; stuck: wait to be fired
.step:
    mov     [rbx + H_DIR], al
    lea     rcx, [dir_dx]
    movsx   edx, byte [rcx + rax]
    add     r12d, edx
    lea     rcx, [dir_dy]
    movsx   edx, byte [rcx + rax]
    add     r13d, edx
    mov     [rbx + H_X], r12b
    mov     [rbx + H_Y], r13b
.done:
    add     rsp, 40
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret
