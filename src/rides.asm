; rides.asm - ride breakdowns, repairs and ticket prices. Every attraction tile has
; a price the player sets and a value guests judge it against: fixed for flat
; rides, and set by excitement for coasters.

%include "defs.inc"

global change_price, fix_ride, ride_breakdowns, ride_value
extern broken, coaster_of, coasters, cur_x, cur_y, map, play_sound, post_msg, price, rand_n
extern tile_ticket

section .rdata
ride_names  dq 0, 0, 0, rn_coaster, rn_ferris, rn_carousel, rn_food, 0, 0, 0
rn_coaster  db "roller coaster", 0
rn_ferris   db "Ferris wheel", 0
rn_carousel db "carousel", 0
rn_food     db "food stall", 0

m_breakdown db `The %s has broken down! Hire a mechanic to fix it.`, 0
m_fixed     db `A mechanic fixed the %s.`, 0
m_price     db `Ticket price for the %s: $%d.`, 0
m_no_price  db `Point at a ride to change its ticket price.`, 0

section .text

; int ride_value(int idx /*ecx*/) -> what guests reckon a ticket is worth, or 0 if
; the tile isn't a working attraction. Leaf; clobbers eax, rdx.
ride_value:
    lea     rax, [map]
    movzx   eax, byte [rax + rcx]
    cmp     eax, T_STATION
    jne     .flat
    lea     rax, [coaster_of]
    movzx   eax, byte [rax + rcx]
    test    eax, eax
    jz      .none                   ; circuit not finished
    dec     eax
    imul    eax, eax, CO_SIZE
    lea     rdx, [coasters]
    mov     eax, [rdx + rax + CO_TICKET]
    ret
.flat:
    cmp     eax, T_FERRIS
    jb      .none
    cmp     eax, T_FOOD
    ja      .none
    lea     rdx, [tile_ticket]
    mov     eax, [rdx + rax*4]
    ret
.none:
    xor     eax, eax
    ret

; void ride_breakdowns() - once a tick, every working ride may break down
ride_breakdowns:
    push    rbx
    push    rsi
    sub     rsp, 40
    xor     ebx, ebx
.tile:
    lea     rax, [map]
    movzx   esi, byte [rax + rbx]
    mov     ecx, BREAK_ODDS
    cmp     esi, T_FERRIS
    je      .roll
    cmp     esi, T_CAROUSEL
    je      .roll
    cmp     esi, T_STATION          ; coasters only once they're open
    jne     .next
    lea     rax, [coaster_of]
    cmp     byte [rax + rbx], 0
    je      .next
    mov     ecx, COASTER_BREAK_ODDS
.roll:
    lea     rax, [broken]
    cmp     byte [rax + rbx], 0
    jne     .next
    call    rand_n
    test    eax, eax
    jnz     .next
    lea     rax, [broken]
    mov     byte [rax + rbx], 1
    lea     rax, [ride_names]
    mov     rdx, [rax + rsi*8]
    lea     rcx, [m_breakdown]
    call    post_msg
    mov     ecx, SND_BREAK
    mov     edx, SND_NOW
    call    play_sound
.next:
    inc     ebx
    cmp     ebx, MAP_SIZE
    jb      .tile
    add     rsp, 40
    pop     rsi
    pop     rbx
    ret

; void fix_ride(int idx /*ecx*/)
fix_ride:
    push    rbx
    sub     rsp, 32
    mov     ebx, ecx
    lea     rax, [broken]
    mov     byte [rax + rbx], 0
    lea     rax, [map]
    movzx   eax, byte [rax + rbx]
    lea     rcx, [ride_names]
    mov     rdx, [rcx + rax*8]
    lea     rcx, [m_fixed]
    call    post_msg
    mov     ecx, SND_FIXED
    mov     edx, SND_NOW
    call    play_sound
    add     rsp, 32
    pop     rbx
    ret

; void change_price(int delta /*ecx*/) - adjust the ticket price of the ride under the cursor
change_price:
    push    rbx
    push    rsi
    sub     rsp, 40
    mov     esi, ecx
    imul    ebx, dword [cur_y], MAP_W
    add     ebx, [cur_x]
    lea     rax, [map]
    movzx   eax, byte [rax + rbx]
    cmp     eax, T_STATION
    jb      .not_a_ride
    cmp     eax, T_FOOD
    ja      .not_a_ride
    lea     rcx, [ride_names]
    mov     rdx, [rcx + rax*8]
    lea     rcx, [price]
    movzx   eax, byte [rcx + rbx]
    add     eax, esi
    jns     .not_negative
    xor     eax, eax
.not_negative:
    cmp     eax, MAX_PRICE
    jbe     .set
    mov     eax, MAX_PRICE
.set:
    mov     [rcx + rbx], al
    mov     r8d, eax
    lea     rcx, [m_price]
    call    post_msg
    jmp     .done
.not_a_ride:
    lea     rcx, [m_no_price]
    call    post_msg
.done:
    add     rsp, 40
    pop     rsi
    pop     rbx
    ret
