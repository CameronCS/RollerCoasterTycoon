; sound.asm - sound effects, synthesised at startup (no sound files) into in-memory
; WAV files and played with PlaySound. Only one sound plays at a time, so ambient
; sounds (screams, splats) wait for a quiet moment while the player's own actions
; cut in straight away.
;
; Each effect is a list of segments; a segment sweeps from one pitch to another
; with a chosen waveform and fades to a quarter of its volume by the end. Every
; segment's volume is scaled by the master volume from the options screen.

%include "defs.inc"

global init_sound, play_sound, reload_sounds, sound_on, toggle_sound
extern GetTickCount, PlaySoundA, volume

SAMPLE_RATE       equ 11025
WAV_HEADER        equ 44
SOUND_MEM         equ 48000
SND_ASYNC         equ 0x0001
SND_NODEFAULT     equ 0x0002
SND_MEMORY        equ 0x0004

W_SQUARE          equ 0
W_SAW             equ 1
W_NOISE           equ 2
W_SCREAM          equ 3                 ; saw with noise mixed in

section .rdata
;                   segments, then (ms, start Hz, end Hz, waveform, volume 0-100) each
snd_build   dd 2,   40, 220, 140, W_SQUARE, 70,    50, 140, 80, W_SQUARE, 60
snd_cash    dd 3,   40, 1568, 1568, W_SQUARE, 45,  60, 2093, 2093, W_SQUARE, 45,  120, 2637, 2637, W_SQUARE, 40
snd_scream  dd 3,   200, 650, 950, W_SCREAM, 55,   250, 950, 820, W_SCREAM, 65,   300, 820, 520, W_SCREAM, 60
snd_splat   dd 2,   60, 0, 0, W_NOISE, 80,         110, 0, 0, W_NOISE, 45
snd_break   dd 3,   180, 140, 130, W_SQUARE, 65,   180, 120, 110, W_SQUARE, 65,   260, 100, 70, W_SQUARE, 60
snd_fixed   dd 2,   90, 880, 880, W_SQUARE, 50,    160, 1319, 1319, W_SQUARE, 50
snd_fanfare dd 4,   110, 523, 523, W_SQUARE, 50,   110, 659, 659, W_SQUARE, 50,   110, 784, 784, W_SQUARE, 50,   300, 1047, 1047, W_SQUARE, 55
sound_defs  dq snd_build, snd_cash, snd_scream, snd_splat, snd_break, snd_fixed, snd_fanfare

section .data
sound_on    dd 1
noise       dd 0x1234567

section .bss
alignb 16
sound_wav   resq SND_COUNT              ; each effect's WAV file in sound_mem
sound_ms    resd SND_COUNT              ; and how long it lasts
quiet_at    resd 1                      ; tick count when the current sound ends
sound_mem   resb SOUND_MEM

section .text

; int next_noise() -> random byte in al (xorshift). Leaf; clobbers eax, edx.
next_noise:
    mov     eax, [noise]
    mov     edx, eax
    shl     edx, 13
    xor     eax, edx
    mov     edx, eax
    shr     edx, 17
    xor     eax, edx
    mov     edx, eax
    shl     edx, 5
    xor     eax, edx
    mov     [noise], eax
    ret

; void init_sound() - synthesise every effect into sound_mem
init_sound:
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 48                 ; [rsp+32] sample count, [rsp+36] segment index, [rsp+40] sound,
                                    ; [rsp+44] this segment's volume after the master volume

    lea     rdi, [sound_mem]        ; where the next WAV goes
    mov     dword [rsp + 40], 0
.sound:
    mov     eax, [rsp + 40]
    lea     rcx, [sound_defs]
    mov     rsi, [rcx + rax*8]      ; this effect's definition
    lea     rcx, [sound_wav]
    mov     [rcx + rax*8], rdi
    lea     rbx, [rdi + WAV_HEADER] ; sample write pointer
    xor     r15d, r15d              ; oscillator phase, 16.16
    xor     r14d, r14d              ; total milliseconds
    mov     dword [rsp + 36], 0

.segment:
    mov     eax, [rsp + 36]
    cmp     eax, [rsi]
    jae     .wav_header
    imul    eax, eax, 20
    lea     r12, [rsi + 4 + rax]    ; segment fields
    mov     eax, [r12]
    add     r14d, eax
    imul    eax, eax, SAMPLE_RATE
    xor     edx, edx
    mov     ecx, 1000
    div     ecx
    mov     [rsp + 32], eax         ; samples in this segment
    mov     eax, [r12 + 16]
    imul    eax, [volume]
    xor     edx, edx
    mov     ecx, 100
    div     ecx
    mov     [rsp + 44], eax
    xor     r13d, r13d              ; sample index
.sample:
    cmp     r13d, [rsp + 32]
    jae     .next_segment

    mov     eax, [r12 + 8]          ; pitch = start + (end - start) * i / n
    sub     eax, [r12 + 4]
    imul    eax, r13d
    cdq
    idiv    dword [rsp + 32]
    add     eax, [r12 + 4]
    shl     eax, 16                 ; phase step = pitch * 65536 / rate
    xor     edx, edx
    mov     ecx, SAMPLE_RATE
    div     ecx
    add     r15d, eax
    movzx   ecx, r15w               ; where we are in the cycle, 0-65535

    mov     eax, [r12 + 12]         ; waveform, -127..127
    cmp     eax, W_SAW
    je      .saw
    cmp     eax, W_NOISE
    je      .noise
    cmp     eax, W_SCREAM
    je      .scream
    mov     eax, 127                ; square
    cmp     ecx, 0x8000
    jb      .shaped
    mov     eax, -127
    jmp     .shaped
.saw:
    mov     eax, ecx
    shr     eax, 8
    sub     eax, 128
    jmp     .shaped
.noise:
    call    next_noise
    movsx   eax, al
    jmp     .shaped
.scream:                            ; 3/4 saw + 1/4 noise
    mov     r8d, ecx
    shr     r8d, 8
    sub     r8d, 128
    lea     r8d, [r8d * 2 + r8d]
    sar     r8d, 2
    call    next_noise
    movsx   eax, al
    sar     eax, 2
    add     eax, r8d
.shaped:
    ; volume fades from vol to vol/4: sample * vol * (4n - 3i) / (400n)
    imul    eax, [rsp + 44]
    mov     ecx, [rsp + 32]
    shl     ecx, 2
    lea     edx, [r13d * 2 + r13d]
    sub     ecx, edx
    imul    eax, ecx
    mov     ecx, [rsp + 32]
    imul    ecx, ecx, 400
    cdq
    idiv    ecx
    add     eax, 128                ; 8-bit samples are unsigned
    mov     [rbx], al
    inc     rbx
    inc     r13d
    jmp     .sample
.next_segment:
    inc     dword [rsp + 36]
    jmp     .segment

.wav_header:                        ; a canonical 44-byte PCM header: 8-bit mono
    mov     rax, rbx
    sub     rax, rdi
    sub     eax, WAV_HEADER         ; eax = sample bytes
    mov     dword [rdi], 'RIFF'
    lea     ecx, [rax + 36]
    mov     [rdi + 4], ecx
    mov     dword [rdi + 8], 'WAVE'
    mov     dword [rdi + 12], 'fmt '
    mov     dword [rdi + 16], 16
    mov     word [rdi + 20], 1      ; PCM
    mov     word [rdi + 22], 1      ; mono
    mov     dword [rdi + 24], SAMPLE_RATE
    mov     dword [rdi + 28], SAMPLE_RATE
    mov     word [rdi + 32], 1
    mov     word [rdi + 34], 8
    mov     dword [rdi + 36], 'data'
    mov     [rdi + 40], eax
    mov     eax, [rsp + 40]
    lea     rcx, [sound_ms]
    mov     [rcx + rax*4], r14d
    lea     rdi, [rbx + 1]          ; next WAV, word aligned
    and     rdi, -2

    inc     dword [rsp + 40]
    cmp     dword [rsp + 40], SND_COUNT
    jb      .sound

    add     rsp, 48
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; void play_sound(int sound /*ecx*/, int mode /*edx: SND_AMBIENT or SND_NOW*/)
play_sound:
    push    rbx
    push    rsi
    sub     rsp, 40
    cmp     dword [sound_on], 0
    je      .done
    mov     ebx, ecx
    mov     esi, edx
    call    GetTickCount
    cmp     esi, SND_NOW
    je      .play
    cmp     eax, [quiet_at]         ; ambient: only into silence
    js      .done
.play:
    lea     rcx, [sound_ms]
    add     eax, [rcx + rbx*4]
    mov     [quiet_at], eax
    lea     rcx, [sound_wav]
    mov     rcx, [rcx + rbx*8]
    xor     edx, edx
    mov     r8d, SND_MEMORY | SND_ASYNC | SND_NODEFAULT
    call    PlaySoundA
.done:
    add     rsp, 40
    pop     rsi
    pop     rbx
    ret

; void reload_sounds() - stop playback and resynthesise at the current master volume
reload_sounds:
    sub     rsp, 40
    xor     ecx, ecx
    xor     edx, edx
    xor     r8d, r8d
    call    PlaySoundA              ; nothing may be playing from the buffers we rewrite
    call    init_sound
    add     rsp, 40
    ret

; void toggle_sound() - mute or unmute; muting stops whatever is playing
toggle_sound:
    sub     rsp, 40
    xor     dword [sound_on], 1
    jnz     .done
    xor     ecx, ecx
    xor     edx, edx
    xor     r8d, r8d
    call    PlaySoundA
.done:
    add     rsp, 40
    ret
