; coaster.asm - roller coaster circuits: finds each station whose track loops back into
; it, and rates the ride (excitement, drops, splashes, ticket price, nausea).

%include "defs.inc"

global analyze_coasters, circ, coaster_n, coaster_of, coasters
extern dir_dx, dir_dy, height, map

section .bss
alignb 16
coaster_n   resd 1
visit       resb MAP_SIZE           ; circuit tracing scratch
coaster_of  resb MAP_SIZE           ; coaster number + 1 for station/track tiles in a circuit

circ        resw MAP_SIZE           ; circuits: station index, then each track tile in order
coasters    resb MAX_COASTERS * CO_SIZE

section .text

; int neighbor(int idx /*ecx*/, int dir /*edx*/) -> map index, or -1 off-map.
; Leaf; clobbers eax, edx, r8-r10.
neighbor:
    mov     r10d, edx
    mov     eax, ecx
    xor     edx, edx
    mov     r8d, MAP_W
    div     r8d                     ; eax = y, edx = x
    lea     r9, [dir_dx]
    movsx   r8d, byte [r9 + r10]
    add     edx, r8d
    lea     r9, [dir_dy]
    movsx   r8d, byte [r9 + r10]
    add     eax, r8d
    cmp     edx, 0
    jl      .oob
    cmp     edx, MAP_W
    jge     .oob
    cmp     eax, 0
    jl      .oob
    cmp     eax, MAP_H
    jge     .oob
    imul    eax, eax, MAP_W
    add     eax, edx
    ret
.oob:
    mov     eax, -1
    ret

; int free_track(int idx /*ecx*/, int dir /*edx*/) -> neighbouring index if it is
; track not yet visited by the current trace, else -1. Leaf.
free_track:
    call    neighbor
    cmp     eax, -1
    je      .no
    lea     r8, [map]
    cmp     byte [r8 + rax], T_TRACK
    jne     .no
    lea     r8, [visit]
    cmp     byte [r8 + rax], 0
    jne     .no
    ret
.no:
    mov     eax, -1
    ret

; ---------------------------------------------------------------------------
; void analyze_coasters() - find every station whose track loops back into it
; and rate the circuit. Each track tile belongs to at most one coaster.
; ---------------------------------------------------------------------------
analyze_coasters:
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 48                 ; [rsp+32] first dir, [rsp+36] length, [rsp+40] stamp

    xor     eax, eax
    lea     rdi, [visit]
    mov     ecx, MAP_SIZE
    rep     stosb
    lea     rdi, [coaster_of]
    mov     ecx, MAP_SIZE
    rep     stosb
    lea     rdi, [coasters]
    mov     ecx, MAX_COASTERS * CO_SIZE
    rep     stosb
    mov     dword [coaster_n], 0

    lea     rbx, [circ]             ; circuit write pointer
    xor     r13d, r13d              ; scan index = station being traced
.scan:
    lea     rax, [map]
    cmp     byte [rax + r13], T_STATION
    jne     .scan_next
    cmp     dword [coaster_n], MAX_COASTERS
    jae     .scan_next

    mov     eax, [coaster_n]
    imul    eax, eax, CO_SIZE
    lea     r12, [coasters]
    add     r12, rax
    mov     [r12 + CO_STATION], r13d
    mov     rax, rbx
    lea     rcx, [circ]
    sub     rax, rcx
    shr     rax, 1
    mov     [r12 + CO_PATH], eax
    mov     [rbx], r13w
    add     rbx, 2
    mov     eax, [coaster_n]
    inc     eax
    mov     [rsp + 40], eax
    lea     rcx, [visit]
    mov     [rcx + r13], al

    ; leave the station along the first track tile we find
    xor     esi, esi
.first:
    mov     ecx, r13d
    mov     edx, esi
    call    free_track
    cmp     eax, -1
    jne     .got_first
    inc     esi
    cmp     esi, 4
    jb      .first
    jmp     .fail
.got_first:
    mov     [rsp + 32], esi
    mov     r15d, esi               ; direction of travel
    xor     edi, edi                ; turns
    mov     dword [rsp + 36], 0     ; length

.step:
    mov     r14d, eax               ; current tile
    mov     [rbx], r14w
    add     rbx, 2
    inc     dword [rsp + 36]
    mov     ecx, [rsp + 40]
    lea     rdx, [visit]
    mov     [rdx + r14], cl

    ; prefer going straight, then any turn
    mov     ecx, r14d
    mov     edx, r15d
    call    free_track
    cmp     eax, -1
    jne     .step
    xor     esi, esi
.turn:
    cmp     esi, r15d
    je      .next_turn
    mov     ecx, r14d
    mov     edx, esi
    call    free_track
    cmp     eax, -1
    je      .next_turn
    inc     edi
    mov     r15d, esi
    jmp     .step
.next_turn:
    inc     esi
    cmp     esi, 4
    jb      .turn

    ; dead end of fresh track: are we back beside the station?
    xor     esi, esi
.close:
    mov     eax, r15d
    xor     eax, 2
    cmp     esi, eax                ; never straight back the way we came
    je      .next_close
    mov     ecx, r14d
    mov     edx, esi
    call    neighbor
    cmp     eax, r13d
    je      .closed
.next_close:
    inc     esi
    cmp     esi, 4
    jb      .close
    jmp     .fail

.closed:
    cmp     esi, r15d               ; turn into the station?
    je      .no_turn_in
    inc     edi
.no_turn_in:
    cmp     esi, [rsp + 32]         ; turn through the station?
    je      .rate
    inc     edi

.rate:
    ; ride the circuit once: count levels dropped and tiles over water
    lea     rax, [circ]
    mov     ecx, [r12 + CO_PATH]
    lea     r14, [rax + rcx*2]      ; station entry
    lea     r9, [height]
    movzx   eax, word [r14]
    movzx   r15d, byte [r9 + rax]   ; previous height
    xor     esi, esi                ; drops
    mov     ecx, [rsp + 36]
    inc     ecx                     ; every tile, then back into the station
    mov     r8, r14
.ride_step:
    add     r8, 2
    cmp     r8, rbx
    jb      .ride_tile
    mov     r8, r14
.ride_tile:
    movzx   eax, word [r8]
    movzx   eax, byte [r9 + rax]
    mov     edx, r15d
    sub     edx, eax
    jle     .no_drop
    add     esi, edx
.no_drop:
    cmp     eax, SEA_LEVEL
    jae     .dry
    inc     dword [r12 + CO_SPLASH]
.dry:
    mov     r15d, eax
    dec     ecx
    jnz     .ride_step
    mov     [r12 + CO_DROPS], esi

    mov     eax, [rsp + 36]
    mov     [r12 + CO_LEN], eax
    mov     [r12 + CO_TURNS], edi
    imul    ecx, eax, 3             ; excitement = 3*length + 4*turns + 10*drops + 6*splashes
    lea     ecx, [ecx + edi*4]
    imul    eax, esi, 10
    add     ecx, eax
    imul    eax, dword [r12 + CO_SPLASH], 6
    add     ecx, eax
    mov     [r12 + CO_EXCITE], ecx

    mov     eax, ecx                ; ticket = 2 + excitement/6, max $25
    xor     edx, edx
    mov     r8d, 6
    div     r8d
    add     eax, 2
    cmp     eax, 25
    jbe     .ticket_ok
    mov     eax, 25
.ticket_ok:
    mov     [r12 + CO_TICKET], eax

    mov     eax, ecx                ; joy = 10 + excitement/2, max 70
    shr     eax, 1
    add     eax, 10
    cmp     eax, 70
    jbe     .joy_ok
    mov     eax, 70
.joy_ok:
    mov     [r12 + CO_JOY], al

    imul    eax, edi, 6             ; nausea = 5 + 6*turns + length/2 + 4*drops, max 80
    mov     edx, [rsp + 36]
    shr     edx, 1
    add     eax, edx
    lea     eax, [eax + esi*4 + 5]
    cmp     eax, 80
    jbe     .nausea_ok
    mov     eax, 80
.nausea_ok:
    mov     [r12 + CO_NAUSEA], al

    ; claim the circuit's tiles for this coaster
    lea     rax, [circ]
    mov     ecx, [r12 + CO_PATH]
    lea     rax, [rax + rcx*2]
    mov     edx, [rsp + 40]
    lea     r8, [coaster_of]
.claim:
    cmp     rax, rbx
    jae     .claimed
    movzx   ecx, word [rax]
    mov     [r8 + rcx], dl
    add     rax, 2
    jmp     .claim
.claimed:
    inc     dword [coaster_n]
    jmp     .scan_next

.fail:                              ; unwind: free the tiles this trace touched
    lea     rax, [circ]
    mov     ecx, [r12 + CO_PATH]
    lea     rax, [rax + rcx*2]
    mov     rdx, rbx
    mov     rbx, rax
    lea     r8, [visit]
.unwind:
    cmp     rax, rdx
    jae     .scan_next
    movzx   ecx, word [rax]
    mov     byte [r8 + rcx], 0
    add     rax, 2
    jmp     .unwind

.scan_next:
    inc     r13d
    cmp     r13d, MAP_SIZE
    jb      .scan

    add     rsp, 48
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret
