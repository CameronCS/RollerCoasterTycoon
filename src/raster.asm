; raster.asm - the software rasteriser: spans, rectangles, isometric diamonds and
; blocks, circles, rings and Bresenham lines, all drawn into the DIB with the
; colour in [pen] (blocks use pen_top / pen_left / pen_right) and clipped to the screen.

%include "defs.inc"

global box, circle, diamond, fill_rect, hspan, line, pen, pen_left, pen_right, pen_top, pixels, plot
global ring, vspan

section .bss
alignb 16
pixels      resq 1
pen         resd 1
pen_top     resd 1
pen_left    resd 1
pen_right   resd 1

section .text

; void hspan(int x0 /*ecx*/, int x1 /*edx, exclusive*/, int y /*r8d*/). Leaf.
hspan:
    cmp     r8d, 0
    jl      .out
    cmp     r8d, SCR_H
    jge     .out
    test    ecx, ecx
    jns     .left_ok
    xor     ecx, ecx
.left_ok:
    cmp     edx, SCR_W
    jle     .right_ok
    mov     edx, SCR_W
.right_ok:
    cmp     ecx, edx
    jge     .out
    push    rdi
    imul    eax, r8d, SCR_W
    add     eax, ecx
    mov     rdi, [pixels]
    lea     rdi, [rdi + rax*4]
    sub     edx, ecx
    mov     ecx, edx
    mov     eax, [pen]
    rep     stosd
    pop     rdi
.out:
    ret

; void vspan(int x /*ecx*/, int y0 /*edx*/, int y1 /*r8d, exclusive*/). Leaf.
vspan:
    cmp     ecx, 0
    jl      .out
    cmp     ecx, SCR_W
    jge     .out
    test    edx, edx
    jns     .top_ok
    xor     edx, edx
.top_ok:
    cmp     r8d, SCR_H
    jle     .bottom_ok
    mov     r8d, SCR_H
.bottom_ok:
    cmp     edx, r8d
    jge     .out
    imul    eax, edx, SCR_W
    add     eax, ecx
    mov     r10, [pixels]
    lea     r10, [r10 + rax*4]
    sub     r8d, edx
    mov     eax, [pen]
.fill:
    mov     [r10], eax
    add     r10, SCR_W * 4
    dec     r8d
    jnz     .fill
.out:
    ret

; void plot(int x /*ecx*/, int y /*edx*/). Leaf.
plot:
    cmp     ecx, 0
    jl      .out
    cmp     ecx, SCR_W
    jge     .out
    cmp     edx, 0
    jl      .out
    cmp     edx, SCR_H
    jge     .out
    imul    eax, edx, SCR_W
    add     eax, ecx
    mov     r10, [pixels]
    mov     r11d, [pen]
    mov     [r10 + rax*4], r11d
.out:
    ret

; void fill_rect(int x /*ecx*/, int y /*edx*/, int w /*r8d*/, int h /*r9d*/)
fill_rect:
    push    rbx
    push    rsi
    push    rdi
    push    r12
    sub     rsp, 40
    mov     ebx, ecx
    lea     esi, [ecx + r8d]
    mov     edi, edx
    lea     r12d, [edx + r9d]
.row:
    cmp     edi, r12d
    jge     .done
    mov     ecx, ebx
    mov     edx, esi
    mov     r8d, edi
    call    hspan
    inc     edi
    jmp     .row
.done:
    add     rsp, 40
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; void diamond(int cx /*ecx*/, int top /*edx*/, int hw /*r8d, even*/) - a flat
; 2:1 isometric diamond hw*2 wide and hw tall.
diamond:
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    sub     rsp, 32
    mov     ebx, ecx
    mov     esi, edx
    mov     r12d, r8d
    xor     edi, edi                ; row
.row:
    cmp     edi, r12d
    jge     .done
    mov     eax, r12d
    dec     eax
    sub     eax, edi                ; rows left below this one
    cmp     eax, edi
    jle     .half
    mov     eax, edi
.half:
    lea     r13d, [rax*2 + 2]       ; half-width of this row
    mov     ecx, ebx
    sub     ecx, r13d
    lea     edx, [rbx + r13]
    lea     r8d, [rsi + rdi]
    call    hspan
    inc     edi
    jmp     .row
.done:
    add     rsp, 32
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; void box(int cx /*ecx*/, int gy /*edx*/, int hw /*r8d*/, int h /*r9d*/) - an
; isometric block whose footprint diamond has its top corner at (cx, gy),
; raised h pixels: left face pen_left, right face pen_right, lid pen_top.
box:
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14
    sub     rsp, 40
    mov     ebx, ecx
    mov     esi, edx
    mov     r12d, r8d
    mov     r13d, r9d
    mov     r14d, r12d
    shr     r14d, 1                 ; hw/2

    mov     eax, [pen_left]
    mov     [pen], eax
    xor     edi, edi
.left:
    cmp     edi, r12d
    jge     .right_face
    mov     ecx, ebx
    sub     ecx, r12d
    add     ecx, edi
    mov     edx, edi
    shr     edx, 1
    add     edx, r14d
    add     edx, esi                ; bottom edge at this column
    lea     r8d, [rdx + 1]
    sub     edx, r13d
    call    vspan
    inc     edi
    jmp     .left

.right_face:
    mov     eax, [pen_right]
    mov     [pen], eax
    xor     edi, edi
.right:
    cmp     edi, r12d
    jge     .lid
    lea     ecx, [rbx + rdi]
    mov     edx, esi
    add     edx, r12d
    mov     eax, edi
    shr     eax, 1
    sub     edx, eax
    lea     r8d, [rdx + 1]
    sub     edx, r13d
    call    vspan
    inc     edi
    jmp     .right

.lid:
    mov     eax, [pen_top]
    mov     [pen], eax
    mov     ecx, ebx
    mov     edx, esi
    sub     edx, r13d
    mov     r8d, r12d
    call    diamond

    add     rsp, 40
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; int circle_half(int r /*r12d*/, int dy /*edi*/) -> widest w with w^2+dy^2 <= r^2. Leaf.
circle_half:
    mov     r8d, r12d
    imul    r8d, r8d
    mov     r9d, edi
    imul    r9d, r9d
    mov     eax, r12d
.shrink:
    mov     ecx, eax
    imul    ecx, ecx
    add     ecx, r9d
    cmp     ecx, r8d
    jle     .done
    dec     eax
    jmp     .shrink
.done:
    ret

; void circle(int cx /*ecx*/, int cy /*edx*/, int r /*r8d*/) - filled disc
circle:
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    sub     rsp, 32
    mov     ebx, ecx
    mov     esi, edx
    mov     r12d, r8d
    mov     edi, r12d
    neg     edi                     ; dy
.row:
    cmp     edi, r12d
    jg      .done
    call    circle_half
    mov     r13d, eax
    mov     ecx, ebx
    sub     ecx, r13d
    lea     edx, [rbx + r13 + 1]
    lea     r8d, [rsi + rdi]
    call    hspan
    inc     edi
    jmp     .row
.done:
    add     rsp, 32
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; void ring(int cx /*ecx*/, int cy /*edx*/, int r /*r8d*/) - circle outline
ring:
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    sub     rsp, 32
    mov     ebx, ecx
    mov     esi, edx
    mov     r12d, r8d
    mov     edi, r12d
    neg     edi
.row:
    cmp     edi, r12d
    jg      .done
    call    circle_half
    mov     r13d, eax
    mov     ecx, ebx
    sub     ecx, r13d
    lea     edx, [rsi + rdi]
    call    plot
    lea     ecx, [rbx + r13]
    lea     edx, [rsi + rdi]
    call    plot
    lea     ecx, [rbx + rdi]
    mov     edx, esi
    sub     edx, r13d
    call    plot
    lea     ecx, [rbx + rdi]
    lea     edx, [rsi + r13]
    call    plot
    inc     edi
    jmp     .row
.done:
    add     rsp, 32
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; void line(int x0 /*ecx*/, int y0 /*edx*/, int x1 /*r8d*/, int y1 /*r9d*/) - Bresenham
line:
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 48                 ; [rsp+32] y step, [rsp+36] error
    mov     ebx, ecx
    mov     esi, edx
    mov     r12d, r8d
    mov     r13d, r9d

    mov     r14d, r12d              ; dx = |x1-x0|, edi = x step
    sub     r14d, ebx
    mov     edi, 1
    test    r14d, r14d
    jns     .dx_ok
    neg     r14d
    mov     edi, -1
.dx_ok:
    mov     r15d, r13d              ; dy = -|y1-y0|
    sub     r15d, esi
    mov     eax, 1
    test    r15d, r15d
    jns     .dy_ok
    neg     r15d
    mov     eax, -1
.dy_ok:
    neg     r15d
    mov     [rsp + 32], eax
    lea     eax, [r14d + r15d]
    mov     [rsp + 36], eax

.step:
    mov     ecx, ebx
    mov     edx, esi
    call    plot
    cmp     ebx, r12d
    jne     .continue
    cmp     esi, r13d
    je      .done
.continue:
    mov     eax, [rsp + 36]
    add     eax, eax
    cmp     eax, r15d
    jl      .no_x
    add     [rsp + 36], r15d
    add     ebx, edi
.no_x:
    cmp     eax, r14d
    jg      .step
    add     [rsp + 36], r14d
    add     esi, [rsp + 32]
    jmp     .step
.done:
    add     rsp, 48
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret
