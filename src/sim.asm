; sim.asm - the simulation tick: guests (moods, rides, vomit, wandering), handymen,
; admissions, and the end-of-day accounts and scenario check.

%include "defs.inc"

global sim_tick
extern cash, coaster_n, coaster_of, coasters, compute_stats, day, dir_dx, dir_dy, game_over
extern guest_count, guests, handy_n, handymen, height, map, next_id, post_msg, rand_n, rating
extern ride_count, swept, tick, tile_at, tile_joy, tile_nausea, tile_ticket, tile_upkeep, visitors

section .rdata
tile_thought dq 0, 0, 0, 0, th_ferris, th_carousel, th_food, 0, 0, 0
th_coaster  db `Guest %d: "WOW! That roller coaster was AMAZING!"`, 0
th_tame     db `Guest %d: "That coaster was a bit tame."`, 0
th_ferris   db `Guest %d: "What a lovely view from the Ferris wheel."`, 0
th_carousel db `Guest %d: "The carousel was really fun!"`, 0
th_food     db `Guest %d: "This burger is great value."`, 0
m_hungry    db `Guest %d: "I'm hungry."`, 0
m_puke      db `Guest %d was sick on the path! Yuck. (Hire a handyman to keep things clean)`, 0
m_leave_sad db `Guest %d: "I want to go home." (left the park)`, 0
m_leave_broke db `Guest %d: "I've spent all my money!" (left the park)`, 0
m_disgust   db `Guest %d: "The paths in this park are disgusting!"`, 0
m_newday    db `Day %d begins. Paid $%d in upkeep and wages.`, 0

section .text

; ---------------------------------------------------------------------------
; Guest helpers - rbx = guest record, ecx = amount. Leaf.
; ---------------------------------------------------------------------------
add_happy:
    movzx   eax, byte [rbx + G_HAPPY]
    add     eax, ecx
    cmp     eax, 100
    jbe     .store
    mov     eax, 100
.store:
    mov     [rbx + G_HAPPY], al
    ret

sub_happy:
    movzx   eax, byte [rbx + G_HAPPY]
    sub     eax, ecx
    jns     .store
    xor     eax, eax
.store:
    mov     [rbx + G_HAPPY], al
    ret

add_nausea:
    movzx   eax, byte [rbx + G_NAUSEA]
    add     eax, ecx
    cmp     eax, 100
    jbe     .store
    mov     eax, 100
.store:
    mov     [rbx + G_NAUSEA], al
    ret

; int dir_walkable(int dir /*ecx*/) - from the walker at (r12d, r13d): a path tile
; no more than one level up or down. Leaf.
dir_walkable:
    lea     rax, [dir_dx]
    movsx   r8d, byte [rax + rcx]
    lea     rax, [dir_dy]
    movsx   edx, byte [rax + rcx]
    lea     ecx, [r8d + r12d]
    add     edx, r13d
    call    tile_at
    cmp     eax, T_PATH
    je      .step
    cmp     eax, T_ENTRANCE
    je      .step
    cmp     eax, T_PUKE
    je      .step
.no:
    xor     eax, eax
    ret
.step:
    lea     r8, [height]
    imul    eax, edx, MAP_W
    add     eax, ecx
    movzx   eax, byte [r8 + rax]
    imul    ecx, r13d, MAP_W
    add     ecx, r12d
    movzx   ecx, byte [r8 + rcx]
    sub     eax, ecx
    inc     eax                     ; -1..1 -> 0..2
    cmp     eax, 2
    ja      .no
    mov     eax, 1
    ret

; ---------------------------------------------------------------------------
; int pick_dir(int dir /*ecx*/) - where the walker at (r12d, r13d) goes next:
; usually straight on, otherwise a random branch, turning back only at dead
; ends. Returns -1 when there is no path at all.
; ---------------------------------------------------------------------------
pick_dir:
    push    rsi
    push    rdi
    push    r14
    push    r15
    sub     rsp, 40                 ; [rsp+32..35] = candidate directions
    mov     esi, ecx

    mov     ecx, 10
    call    rand_n
    cmp     eax, 7
    jae     .choose
    mov     ecx, esi
    call    dir_walkable
    test    eax, eax
    jz      .choose
    mov     eax, esi
    jmp     .done

.choose:
    xor     edi, edi                ; candidate count
    xor     r14d, r14d              ; direction
    mov     r15d, esi
    xor     r15d, 2                 ; reverse direction
.candidate:
    cmp     r14d, r15d
    je      .next_candidate
    mov     ecx, r14d
    call    dir_walkable
    test    eax, eax
    jz      .next_candidate
    mov     [rsp + 32 + rdi], r14b
    inc     edi
.next_candidate:
    inc     r14d
    cmp     r14d, 4
    jb      .candidate

    test    edi, edi
    jnz     .pick
    mov     ecx, r15d               ; dead end: turn around
    call    dir_walkable
    test    eax, eax
    jz      .stuck
    mov     eax, r15d
    jmp     .done
.pick:
    mov     ecx, edi
    call    rand_n
    movzx   eax, byte [rsp + 32 + rax]
    jmp     .done
.stuck:
    mov     eax, -1
.done:
    add     rsp, 40
    pop     r15
    pop     r14
    pop     rdi
    pop     rsi
    ret

; ---------------------------------------------------------------------------
; void update_guest(Guest* g /*rcx*/) - one tick of a guest's life.
; ---------------------------------------------------------------------------
update_guest:
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 32
    mov     rbx, rcx
    movzx   r12d, byte [rbx + G_X]
    movzx   r13d, byte [rbx + G_Y]
    mov     [rbx + G_PX], r12b
    mov     [rbx + G_PY], r13b

    movzx   eax, byte [rbx + G_COOL]
    test    eax, eax
    jz      .hunger
    dec     eax                     ; still on a ride
    mov     [rbx + G_COOL], al
    jmp     .done

.hunger:
    mov     ecx, 8
    call    rand_n
    test    eax, eax
    jnz     .nausea
    movzx   eax, byte [rbx + G_HUNGER]
    cmp     eax, 100
    jae     .nausea
    inc     eax
    mov     [rbx + G_HUNGER], al
    cmp     eax, 75
    jne     .nausea
    lea     rcx, [m_hungry]
    mov     edx, [rbx + G_ID]
    call    post_msg

.nausea:
    cmp     byte [rbx + G_NAUSEA], 0
    je      .mood
    mov     ecx, 4
    call    rand_n
    test    eax, eax
    jnz     .mood
    dec     byte [rbx + G_NAUSEA]

.mood:
    mov     ecx, 12                 ; boredom
    call    rand_n
    test    eax, eax
    jnz     .starving
    mov     ecx, 1
    call    sub_happy
.starving:
    cmp     byte [rbx + G_HUNGER], 70
    jb      .puke
    mov     ecx, 6
    call    rand_n
    test    eax, eax
    jnz     .puke
    mov     ecx, 1
    call    sub_happy

.puke:
    cmp     byte [rbx + G_NAUSEA], 50
    jb      .leave_check
    mov     ecx, 30
    call    rand_n
    test    eax, eax
    jnz     .leave_check
    mov     byte [rbx + G_NAUSEA], 5
    mov     ecx, 5
    call    sub_happy
    mov     ecx, r12d
    mov     edx, r13d
    call    tile_at
    cmp     eax, T_PATH
    jne     .leave_check
    imul    eax, r13d, MAP_W
    add     eax, r12d
    lea     rcx, [map]
    mov     byte [rcx + rax], T_PUKE
    lea     rcx, [m_puke]
    mov     edx, [rbx + G_ID]
    call    post_msg

.leave_check:
    cmp     byte [rbx + G_HAPPY], 15
    jae     .broke_check
    lea     rcx, [m_leave_sad]
    jmp     .leave
.broke_check:
    cmp     dword [rbx + G_CASH], 3
    jge     .attractions
    lea     rcx, [m_leave_broke]
.leave:
    mov     edx, [rbx + G_ID]
    call    post_msg
    mov     byte [rbx + G_ACTIVE], 0
    jmp     .done

    ; look at the four neighbouring tiles for something to do
.attractions:
    xor     esi, esi
.look:
    lea     rax, [dir_dx]
    movsx   ecx, byte [rax + rsi]
    add     ecx, r12d
    lea     rax, [dir_dy]
    movsx   edx, byte [rax + rsi]
    add     edx, r13d
    call    tile_at
    mov     edi, eax
    imul    r14d, edx, MAP_W        ; neighbour's map index (used for stations)
    add     r14d, ecx

    cmp     edi, T_TREE
    jne     .ride
    mov     ecx, 12
    call    rand_n
    test    eax, eax
    jnz     .next_look
    mov     ecx, 1
    call    add_happy
    jmp     .next_look

.ride:
    cmp     edi, T_STATION
    jb      .next_look
    cmp     edi, T_FOOD
    ja      .next_look
    mov     ecx, 3
    call    rand_n
    test    eax, eax
    jnz     .next_look
    cmp     edi, T_FOOD
    jne     .variety
    cmp     byte [rbx + G_HUNGER], 40
    jb      .next_look
    jmp     .board
.variety:
    movzx   eax, byte [rbx + G_LAST]
    cmp     eax, edi
    jne     .board
    mov     ecx, 4                  ; mostly want something different
    call    rand_n
    test    eax, eax
    jnz     .next_look

.board:
    cmp     edi, T_STATION
    je      .coaster
    lea     rax, [tile_ticket]
    mov     ecx, [rax + rdi*4]
    cmp     [rbx + G_CASH], ecx
    jl      .next_look
    sub     [rbx + G_CASH], ecx
    add     [cash], ecx
    lea     rax, [tile_joy]
    mov     ecx, [rax + rdi*4]
    call    add_happy
    lea     rax, [tile_nausea]
    mov     ecx, [rax + rdi*4]
    call    add_nausea
    mov     byte [rbx + G_COOL], RIDE_TICKS
    lea     rax, [tile_thought]
    mov     r15, [rax + rdi*8]
    jmp     .rode

.coaster:
    lea     rax, [coaster_of]
    movzx   eax, byte [rax + r14]
    test    eax, eax
    jz      .next_look              ; circuit not finished
    dec     eax
    imul    eax, eax, CO_SIZE
    lea     r15, [coasters]
    add     r15, rax
    cmp     byte [rbx + G_NAUSEA], QUEASY_LIMIT
    ja      .next_look
    mov     ecx, [r15 + CO_TICKET]
    cmp     [rbx + G_CASH], ecx
    jl      .next_look
    sub     [rbx + G_CASH], ecx
    add     [cash], ecx
    movzx   ecx, byte [r15 + CO_JOY]
    call    add_happy
    movzx   ecx, byte [r15 + CO_NAUSEA]
    call    add_nausea
    mov     eax, [r15 + CO_LEN]     ; one lap
    inc     eax
    cmp     eax, 250
    jbe     .lap
    mov     eax, 250
.lap:
    mov     [rbx + G_COOL], al
    cmp     [r15 + CO_RUN], eax
    jae     .train_running
    mov     [r15 + CO_RUN], eax
.train_running:
    cmp     dword [r15 + CO_EXCITE], TAME_EXCITEMENT
    lea     r15, [th_coaster]
    jae     .rode
    lea     r15, [th_tame]

.rode:
    mov     [rbx + G_LAST], dil
    cmp     edi, T_FOOD
    jne     .thought
    mov     byte [rbx + G_HUNGER], 0
.thought:
    mov     ecx, 3
    call    rand_n
    test    eax, eax
    jnz     .done
    mov     rcx, r15
    mov     edx, [rbx + G_ID]
    call    post_msg
    jmp     .done

.next_look:
    inc     esi
    cmp     esi, 4
    jb      .look

    ; walk
    movzx   ecx, byte [rbx + G_DIR]
    call    pick_dir
    cmp     eax, -1
    je      .stranded
    mov     esi, eax
    mov     [rbx + G_DIR], sil
    lea     rax, [dir_dx]
    movsx   ecx, byte [rax + rsi]
    add     r12d, ecx
    lea     rax, [dir_dy]
    movsx   ecx, byte [rax + rsi]
    add     r13d, ecx
    mov     [rbx + G_X], r12b
    mov     [rbx + G_Y], r13b

    mov     ecx, r12d
    mov     edx, r13d
    call    tile_at
    cmp     eax, T_PUKE
    jne     .done
    mov     ecx, 3
    call    sub_happy
    mov     ecx, 6
    call    rand_n
    test    eax, eax
    jnz     .done
    lea     rcx, [m_disgust]
    mov     edx, [rbx + G_ID]
    call    post_msg
    jmp     .done

.stranded:                          ; path was demolished under them
    mov     byte [rbx + G_ACTIVE], 0

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

; ---------------------------------------------------------------------------
; void try_spawn() - maybe admit a new guest; more attractions = more guests.
; ---------------------------------------------------------------------------
try_spawn:
    push    rbx
    sub     rsp, 32

    mov     eax, [ride_count]
    test    eax, eax
    jnz     .appeal
    mov     ebx, 3                  ; a few curious visitors to an empty park
    jmp     .roll
.appeal:
    imul    ebx, eax, 4
    imul    eax, dword [coaster_n], 6   ; coasters are the big draw
    add     ebx, eax
    mov     eax, [rating]
    xor     edx, edx
    mov     ecx, 10
    div     ecx
    add     ebx, eax
    cmp     ebx, 60
    jbe     .roll
    mov     ebx, 60
.roll:
    mov     ecx, 100
    call    rand_n
    cmp     eax, ebx
    jae     .done

    lea     rbx, [guests]
    xor     ecx, ecx
.find:
    cmp     byte [rbx + G_ACTIVE], 0
    je      .found
    add     rbx, GUEST_SIZE
    inc     ecx
    cmp     ecx, MAX_GUESTS
    jb      .find
    jmp     .done                   ; park is full

.found:
    mov     byte [rbx + G_ACTIVE], 1
    mov     byte [rbx + G_X], ENTRY_X
    mov     byte [rbx + G_Y], ENTRY_Y
    mov     byte [rbx + G_PX], ENTRY_X
    mov     byte [rbx + G_PY], ENTRY_Y
    mov     byte [rbx + G_DIR], 1
    mov     byte [rbx + G_NAUSEA], 0
    mov     byte [rbx + G_COOL], 0
    mov     byte [rbx + G_LAST], 0
    mov     ecx, 25
    call    rand_n
    add     eax, 65
    mov     [rbx + G_HAPPY], al
    mov     ecx, 30
    call    rand_n
    mov     [rbx + G_HUNGER], al
    mov     ecx, 50
    call    rand_n
    add     eax, 20
    mov     [rbx + G_CASH], eax
    mov     eax, [next_id]
    inc     eax
    mov     [next_id], eax
    mov     [rbx + G_ID], eax
    add     dword [cash], ADMISSION
    inc     dword [visitors]
.done:
    add     rsp, 32
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; void new_day() - pay upkeep and wages, check the scenario objective.
; ---------------------------------------------------------------------------
new_day:
    push    rbx
    push    rsi
    sub     rsp, 40

    inc     dword [day]
    imul    ebx, dword [handy_n], HANDY_WAGE
    xor     esi, esi
    lea     r8, [map]
    lea     r9, [tile_upkeep]
.upkeep:
    movzx   eax, byte [r8 + rsi]
    add     ebx, [r9 + rax*4]
    inc     esi
    cmp     esi, MAP_SIZE
    jb      .upkeep
    sub     [cash], ebx

    cmp     dword [cash], BANKRUPT_LIMIT
    jge     .solvent
    mov     dword [game_over], GO_BANKRUPT
    jmp     .done
.solvent:
    cmp     dword [day], GOAL_DAY
    jle     .announce
    cmp     dword [guest_count], GOAL_GUESTS
    jl      .lose
    mov     dword [game_over], GO_WIN
    jmp     .done
.lose:
    mov     dword [game_over], GO_LOSE
    jmp     .done
.announce:
    lea     rcx, [m_newday]
    mov     edx, [day]
    mov     r8d, ebx
    call    post_msg
.done:
    add     rsp, 40
    pop     rsi
    pop     rbx
    ret

; ---------------------------------------------------------------------------
; void sim_tick()
; ---------------------------------------------------------------------------
sim_tick:
    push    rbx
    push    rsi
    sub     rsp, 40

    inc     dword [tick]
    cmp     dword [tick], TICKS_PER_DAY
    jb      .spawn
    mov     dword [tick], 0
    call    new_day
    cmp     dword [game_over], GO_NONE
    jne     .done

.spawn:
    call    try_spawn
    lea     rbx, [guests]
    xor     esi, esi
.guest:
    cmp     byte [rbx + G_ACTIVE], 0
    je      .next_guest
    mov     rcx, rbx
    call    update_guest
.next_guest:
    add     rbx, GUEST_SIZE
    inc     esi
    cmp     esi, MAX_GUESTS
    jb      .guest

    lea     rbx, [handymen]
    xor     esi, esi
.handy:
    cmp     byte [rbx + H_ACTIVE], 0
    je      .next_handy
    mov     rcx, rbx
    call    update_handy
.next_handy:
    add     rbx, HANDY_SIZE
    inc     esi
    cmp     esi, MAX_HANDY
    jb      .handy

    ; trains run while anyone is aboard, then coast home to the station
    lea     rax, [coasters]
    xor     ecx, ecx
.train:
    cmp     ecx, [coaster_n]
    jae     .trains_done
    mov     dword [rax + CO_MOVED], 0
    cmp     dword [rax + CO_RUN], 0
    je      .coast
    dec     dword [rax + CO_RUN]
    jmp     .advance
.coast:
    cmp     dword [rax + CO_TRAIN], 0
    je      .next_train
.advance:
    mov     dword [rax + CO_MOVED], 1
    mov     edx, [rax + CO_TRAIN]
    inc     edx
    cmp     edx, [rax + CO_LEN]
    jbe     .move_train             ; circuit is LEN track tiles + the station
    xor     edx, edx
.move_train:
    mov     [rax + CO_TRAIN], edx
.next_train:
    add     rax, CO_SIZE
    inc     ecx
    jmp     .train
.trains_done:
    call    compute_stats
.done:
    add     rsp, 40
    pop     rsi
    pop     rbx
    ret

; ===========================================================================
; Rasteriser - everything draws with the colour in [pen] (boxes use pen_top,
; pen_left and pen_right) and clips to the screen.
