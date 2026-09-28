; park.asm - the park itself: starting a new game, generating terrain, and every
; build / demolish / landscape / hire action the player can take.

%include "defs.inc"

global build, compute_stats, demolish_here, init_game
extern analyze_coasters, broken, cash, coaster_n, coaster_of, coasters, cur_x, cur_y, day, drag
extern game_over, guest_count, guests, handy_n, handymen, height, map, mech_n, n_handy, n_landscape
extern n_mech, next_id, paused, play_sound, post_msg, price, rand_n, rating, ride_count, swept, tick
extern tile_cost, tile_name, tile_ticket, tool, tool_tile, visitors

section .rdata
m_welcome   db `Welcome to your new park! Build attractions beside the path. Goal: %d guests by end of day %d.`, 0
m_cleaned   db `Cleaned up the vomit.`, 0
m_demolished db `Demolished %s, refunded $%d.`, 0
m_nothing   db `Nothing to demolish here.`, 0
m_occupied  db `Can't build there - demolish what's there first.`, 0
m_broke     db `Not enough cash! %s costs $%d.`, 0
m_built     db `Built %s for $%d.`, 0
m_coaster_open db `Coaster complete! Excitement %d, ticket price $%d. Let the screaming begin.`, 0
m_hired     db `Hired a handyman for $%d. Wages are $%d a day.`, 0
m_hired_mech db `Hired a mechanic for $%d. Wages are $%d a day.`, 0
m_fired     db `Fired a handyman.`, 0
m_fired_mech db `Fired a mechanic.`, 0
m_hire_where db `Staff have to be placed on a path.`, 0
m_staff_full db `You can't hire any more staff.`, 0
m_tf_clear  db `Only bare land and paths can be raised or lowered.`, 0
m_tf_top    db `The land can't go any higher.`, 0
m_tf_bottom db `The land can't go any lower.`, 0
m_tf_path   db `Paths can't go under water.`, 0
m_raised    db `Raised the land to height %d.`, 0
m_lowered   db `Lowered the land to height %d.`, 0
m_lake      db `Dug out a lake. Coaster track can run over water!`, 0
m_on_water  db `You can't build that on water - only coaster track can go over it.`, 0

section .text

; ---------------------------------------------------------------------------
; void init_game() - fresh park: grass, trees, entrance and a stub of path.
; ---------------------------------------------------------------------------
init_game:
    sub     rsp, 40

    lea     rax, [map]
    lea     rdx, [broken]
    xor     ecx, ecx
.grass:
    mov     byte [rax + rcx], T_GRASS
    mov     byte [rdx + rcx], 0
    inc     ecx
    cmp     ecx, MAP_SIZE
    jb      .grass

    lea     rax, [guests]
    xor     ecx, ecx
.clear:
    mov     byte [rax + rcx], 0
    inc     ecx
    cmp     ecx, MAX_GUESTS * GUEST_SIZE
    jb      .clear

    lea     rax, [handymen]
    xor     ecx, ecx
.clear_staff:
    mov     byte [rax + rcx], 0
    inc     ecx
    cmp     ecx, MAX_HANDY * HANDY_SIZE
    jb      .clear_staff

    call    gen_terrain

    ; scatter some trees (never on the entrance row, never in a lake)
    mov     r10d, START_TREES
.tree:
    mov     ecx, MAP_H
    call    rand_n
    cmp     eax, ENTRY_Y
    je      .tree
    imul    r9d, eax, MAP_W
    mov     ecx, MAP_W
    call    rand_n
    add     r9d, eax
    lea     rax, [height]
    cmp     byte [rax + r9], SEA_LEVEL
    jb      .tree
    lea     rax, [map]
    mov     byte [rax + r9], T_TREE
    dec     r10d
    jnz     .tree

    lea     rax, [map + ENTRY_Y * MAP_W + ENTRY_X]
    mov     byte [rax], T_ENTRANCE
    mov     ecx, 1
.path:
    mov     byte [rax + rcx], T_PATH
    inc     ecx
    cmp     ecx, 6
    jb      .path

    mov     dword [cash], START_CASH
    mov     dword [day], 1
    mov     dword [tick], 0
    mov     dword [cur_x], 6
    mov     dword [cur_y], ENTRY_Y
    mov     dword [tool], 0
    mov     dword [drag], 0
    mov     dword [paused], 0
    mov     dword [game_over], GO_NONE
    mov     dword [next_id], 0
    mov     dword [visitors], 0
    mov     dword [handy_n], 0
    mov     dword [mech_n], 0
    mov     dword [swept], 0
    call    analyze_coasters
    call    compute_stats

    lea     rcx, [m_welcome]
    mov     edx, GOAL_GUESTS
    mov     r8d, GOAL_DAY
    call    post_msg
    add     rsp, 40
    ret

; ---------------------------------------------------------------------------
; void gen_terrain() - rolling land: flat ground, a few terraced hills, a couple
; of lakes, and a level approach to the entrance.
; ---------------------------------------------------------------------------
gen_terrain:
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 32

    lea     rbx, [height]
    xor     ecx, ecx
.flat:
    mov     byte [rbx + rcx], SEA_LEVEL
    inc     ecx
    cmp     ecx, MAP_SIZE
    jb      .flat

    ; hills and lakes both stamp a diamond around a random centre:
    ; a hill rises to peak - distance, a lake is everything within radius
    mov     r15d, START_HILLS + START_LAKES
.feature:
    mov     ecx, MAP_W
    call    rand_n
    mov     r12d, eax               ; centre x
    mov     ecx, MAP_H
    call    rand_n
    mov     r13d, eax               ; centre y
    mov     ecx, 3
    call    rand_n
    mov     r14d, eax
    cmp     r15d, START_LAKES
    jbe     .lake_size
    add     r14d, 2                 ; hill peak 2-4
    jmp     .stamp
.lake_size:
    shr     r14d, 1
    inc     r14d                    ; lake radius 1-2
.stamp:
    xor     esi, esi                ; y
.stamp_row:
    xor     edi, edi                ; x
.stamp_tile:
    mov     eax, edi                ; Manhattan distance to the centre
    sub     eax, r12d
    jns     .dx_ok
    neg     eax
.dx_ok:
    mov     ecx, esi
    sub     ecx, r13d
    jns     .dy_ok
    neg     ecx
.dy_ok:
    add     eax, ecx
    imul    edx, esi, MAP_W
    add     edx, edi
    cmp     r15d, START_LAKES
    jbe     .lake
    mov     ecx, r14d
    sub     ecx, eax                ; hill height here
    cmp     cl, [rbx + rdx]
    jle     .next_tile
    mov     [rbx + rdx], cl
    jmp     .next_tile
.lake:
    cmp     eax, r14d
    ja      .next_tile
    mov     byte [rbx + rdx], 0
.next_tile:
    inc     edi
    cmp     edi, MAP_W
    jb      .stamp_tile
    inc     esi
    cmp     esi, MAP_H
    jb      .stamp_row
    dec     r15d
    jnz     .feature

    ; keep the approach to the entrance level
    mov     esi, ENTRY_Y - 1
.approach_row:
    imul    edx, esi, MAP_W
    xor     edi, edi
.approach:
    lea     eax, [rdx + rdi]
    mov     byte [rbx + rax], SEA_LEVEL
    inc     edi
    cmp     edi, 8
    jb      .approach
    inc     esi
    cmp     esi, ENTRY_Y + 1
    jbe     .approach_row

    add     rsp, 32
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; void compute_stats() - ride_count, guest_count, rating (avg happiness). Leaf.
compute_stats:
    mov     eax, [coaster_n]
    xor     ecx, ecx
    lea     r8, [map]
.tiles:
    movzx   edx, byte [r8 + rcx]
    cmp     edx, T_FERRIS
    jb      .next_tile
    cmp     edx, T_FOOD
    ja      .next_tile
    inc     eax
.next_tile:
    inc     ecx
    cmp     ecx, MAP_SIZE
    jb      .tiles
    mov     [ride_count], eax

    xor     eax, eax
    xor     r9d, r9d
    xor     ecx, ecx
    lea     r8, [guests]
.guests:
    cmp     byte [r8 + G_ACTIVE], 0
    je      .next_guest
    inc     eax
    movzx   edx, byte [r8 + G_HAPPY]
    add     r9d, edx
.next_guest:
    add     r8, GUEST_SIZE
    inc     ecx
    cmp     ecx, MAX_GUESTS
    jb      .guests
    mov     [guest_count], eax

    test    eax, eax
    jnz     .average
    mov     dword [rating], 50
    ret
.average:
    mov     ecx, eax
    mov     eax, r9d
    xor     edx, edx
    div     ecx
    mov     [rating], eax
    ret

; Handyman* handy_at_cursor() -> rax, or 0. Leaf.
handy_at_cursor:
    lea     rax, [handymen]
    xor     ecx, ecx
.loop:
    cmp     byte [rax + H_ACTIVE], 0
    je      .next
    movzx   edx, byte [rax + H_X]
    cmp     edx, [cur_x]
    jne     .next
    movzx   edx, byte [rax + H_Y]
    cmp     edx, [cur_y]
    je      .found
.next:
    add     rax, HANDY_SIZE
    inc     ecx
    cmp     ecx, MAX_HANDY
    jb      .loop
    xor     eax, eax
.found:
    ret

; ---------------------------------------------------------------------------
; void build() - apply the current tool at the cursor.
; ---------------------------------------------------------------------------
build:
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    sub     rsp, 32

    mov     r12d, [coaster_n]
    imul    eax, dword [cur_y], MAP_W
    add     eax, [cur_x]
    lea     r13, [height]
    add     r13, rax                ; r13 = &height under cursor
    lea     rbx, [map]
    add     rbx, rax                ; rbx = &tile under cursor
    movzx   esi, byte [rbx]         ; current tile
    mov     eax, [tool]
    lea     rcx, [tool_tile]
    movzx   edi, byte [rcx + rax]   ; tile to place
    cmp     edi, TOOL_HANDY
    je      .hire
    cmp     edi, TOOL_MECH
    je      .hire
    cmp     edi, TOOL_RAISE
    je      .terraform
    cmp     edi, TOOL_LOWER
    je      .terraform
    test    edi, edi
    jnz     .place

    ; demolish: staff first, then vomit, then whatever is built here
    call    handy_at_cursor
    test    rax, rax
    jz      .demolish_tile
    mov     byte [rax + H_ACTIVE], 0
    lea     rcx, [m_fired]
    cmp     byte [rax + H_TYPE], STAFF_MECH
    je      .fire_mechanic
    dec     dword [handy_n]
    jmp     .fired
.fire_mechanic:
    dec     dword [mech_n]
    lea     rcx, [m_fired_mech]
.fired:
    call    post_msg
    jmp     .success

.demolish_tile:
    cmp     esi, T_GRASS
    je      .nothing
    cmp     esi, T_ENTRANCE
    je      .nothing
    cmp     esi, T_PUKE
    jne     .demolish
    mov     byte [rbx], T_PATH
    lea     rcx, [m_cleaned]
    call    post_msg
    jmp     .success

.demolish:
    lea     rax, [tile_cost]
    mov     r8d, [rax + rsi*4]
    shr     r8d, 1                  ; half refund
    add     [cash], r8d
    mov     byte [rbx], T_GRASS
    lea     rax, [map]              ; nothing left here to be broken
    mov     rcx, rbx
    sub     rcx, rax
    lea     rax, [broken]
    mov     byte [rax + rcx], 0
    lea     rax, [tile_name]
    mov     rdx, [rax + rsi*8]
    lea     rcx, [m_demolished]
    call    post_msg
    jmp     .success

.nothing:
    lea     rcx, [m_nothing]
    call    post_msg
    jmp     .done

.hire:
    cmp     esi, T_PATH
    je      .hire_pay
    cmp     esi, T_PUKE
    je      .hire_pay
    cmp     esi, T_ENTRANCE
    je      .hire_pay
    lea     rcx, [m_hire_where]
    call    post_msg
    jmp     .done
.hire_pay:
    mov     r8d, HANDY_COST
    lea     rdx, [n_handy]
    cmp     edi, TOOL_MECH
    jne     .hire_cost
    mov     r8d, MECH_COST
    lea     rdx, [n_mech]
.hire_cost:
    cmp     [cash], r8d
    jge     .hire_slot
    lea     rcx, [m_broke]
    call    post_msg
    jmp     .done
.hire_slot:
    lea     rax, [handymen]
    xor     ecx, ecx
.find_slot:
    cmp     byte [rax + H_ACTIVE], 0
    je      .hired
    add     rax, HANDY_SIZE
    inc     ecx
    cmp     ecx, MAX_HANDY
    jb      .find_slot
    lea     rcx, [m_staff_full]
    call    post_msg
    jmp     .done
.hired:
    mov     byte [rax + H_ACTIVE], 1
    mov     ecx, [cur_x]
    mov     [rax + H_X], cl
    mov     [rax + H_PX], cl
    mov     ecx, [cur_y]
    mov     [rax + H_Y], cl
    mov     [rax + H_PY], cl
    mov     byte [rax + H_DIR], 1
    mov     byte [rax + H_BUSY], 0
    mov     word [rax + H_TARGET], NO_TARGET
    cmp     edi, TOOL_MECH
    je      .hired_mechanic
    mov     byte [rax + H_TYPE], STAFF_HANDY
    inc     dword [handy_n]
    sub     dword [cash], HANDY_COST
    lea     rcx, [m_hired]
    mov     edx, HANDY_COST
    mov     r8d, HANDY_WAGE
    call    post_msg
    jmp     .success
.hired_mechanic:
    mov     byte [rax + H_TYPE], STAFF_MECH
    inc     dword [mech_n]
    sub     dword [cash], MECH_COST
    lea     rcx, [m_hired_mech]
    mov     edx, MECH_COST
    mov     r8d, MECH_WAGE
    call    post_msg
    jmp     .success

.place:
    cmp     esi, T_GRASS
    je      .afford
    lea     rcx, [m_occupied]
    call    post_msg
    jmp     .done

.afford:
    cmp     byte [r13], SEA_LEVEL
    jae     .dry_land
    cmp     edi, T_TRACK            ; only track can cross water
    je      .dry_land
    lea     rcx, [m_on_water]
    call    post_msg
    jmp     .done
.dry_land:
    lea     rax, [tile_cost]
    mov     r8d, [rax + rdi*4]
    lea     rax, [tile_name]
    mov     rdx, [rax + rdi*8]
    cmp     [cash], r8d
    jge     .buy
    lea     rcx, [m_broke]
    call    post_msg
    jmp     .done

.buy:
    sub     [cash], r8d
    mov     [rbx], dil
    lea     rax, [map]              ; a new ride: working, at the standard price
    mov     rcx, rbx
    sub     rcx, rax
    lea     rax, [broken]
    mov     byte [rax + rcx], 0
    lea     rax, [tile_ticket]
    mov     eax, [rax + rdi*4]
    lea     r9, [price]
    mov     [r9 + rcx], al
    lea     rcx, [m_built]
    call    post_msg
    jmp     .success

.terraform:                         ; bare land and paths only
    cmp     esi, T_GRASS
    je      .tf_cash
    cmp     esi, T_PATH
    je      .tf_cash
    cmp     esi, T_PUKE
    je      .tf_cash
    lea     rcx, [m_tf_clear]
    call    post_msg
    jmp     .done
.tf_cash:
    cmp     dword [cash], TERRAFORM_COST
    jge     .tf_height
    lea     rcx, [m_broke]
    lea     rdx, [n_landscape]
    mov     r8d, TERRAFORM_COST
    call    post_msg
    jmp     .done
.tf_height:
    movzx   edx, byte [r13]
    cmp     edi, TOOL_LOWER
    je      .lower
    cmp     edx, MAX_H
    jb      .raise
    lea     rcx, [m_tf_top]
    call    post_msg
    jmp     .done
.raise:
    inc     edx
    lea     rcx, [m_raised]
    jmp     .reshape
.lower:
    test    edx, edx
    jnz     .can_lower
    lea     rcx, [m_tf_bottom]
    call    post_msg
    jmp     .done
.can_lower:
    dec     edx
    lea     rcx, [m_lowered]
    cmp     edx, SEA_LEVEL
    jae     .reshape
    cmp     esi, T_GRASS
    je      .flood
    lea     rcx, [m_tf_path]
    call    post_msg
    jmp     .done
.flood:
    lea     rcx, [m_lake]
.reshape:
    mov     [r13], dl
    sub     dword [cash], TERRAFORM_COST
    call    post_msg
.success:
    mov     ecx, SND_BUILD
    mov     edx, SND_NOW
    call    play_sound

.done:
    call    analyze_coasters
    call    compute_stats

    ; did that just finish a coaster?
    cmp     [coaster_n], r12d
    jbe     .out
    lea     rax, [map]
    sub     rbx, rax
    lea     rax, [coaster_of]
    movzx   eax, byte [rax + rbx]
    test    eax, eax
    jz      .out
    dec     eax
    imul    eax, eax, CO_SIZE
    lea     rcx, [coasters]
    add     rcx, rax
    mov     eax, [rcx + CO_STATION] ; open at what the ride is worth
    mov     r8d, [rcx + CO_TICKET]
    lea     rdx, [price]
    mov     [rdx + rax], r8b
    mov     edx, [rcx + CO_EXCITE]
    lea     rcx, [m_coaster_open]
    call    post_msg
    mov     ecx, SND_FANFARE
    mov     edx, SND_NOW
    call    play_sound
.out:
    add     rsp, 32
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; void demolish_here() - demolish at the cursor whatever tool is selected.
demolish_here:
    push    rbx
    sub     rsp, 32
    mov     ebx, [tool]
    mov     dword [tool], TOOL_DEMOLISH
    call    build
    mov     [tool], ebx
    add     rsp, 32
    pop     rbx
    ret
