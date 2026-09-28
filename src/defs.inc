; defs.inc - constants, record layouts and macros shared by every module.
;
; Windows x64 ABI reminders used throughout:
;   int/pointer args: rcx, rdx, r8, r9, then the stack from [rsp+32]   return: rax
;   caller reserves 32 bytes of shadow space, rsp 16-byte aligned at every call
;   nonvolatile: rbx, rsi, rdi, rbp, r12-r15

bits 64
default rel

; ---- window / screen ------------------------------------------------------
SCR_W             equ 1120
SCR_H             equ 720
WIN_STYLE         equ 0x10CA0000        ; WS_VISIBLE|WS_CAPTION|WS_SYSMENU|WS_MINIMIZEBOX
CW_USEDEFAULT     equ 0x80000000
IDC_ARROW         equ 32512
PM_REMOVE         equ 1
SRCCOPY           equ 0x00CC0020
WM_DESTROY        equ 0x0002
WM_PAINT          equ 0x000F
WM_QUIT           equ 0x0012
WM_ERASEBKGND     equ 0x0014
WM_KEYDOWN        equ 0x0100
WM_MOUSEMOVE      equ 0x0200
WM_LBUTTONDOWN    equ 0x0201
WM_LBUTTONUP      equ 0x0202
WM_RBUTTONDOWN    equ 0x0204
WM_RBUTTONUP      equ 0x0205
WM_MOUSEWHEEL     equ 0x020A
MK_LBUTTON        equ 1
MK_RBUTTON        equ 2

; ---- isometric layout -----------------------------------------------------
; Tile (x,y) at height 0 has its top corner at (OX + (x-y)*20, OY + (x+y)*10);
; tiles are 40x20 and each height level lifts a tile HSTEP pixels.
OX                equ 420
OY                equ 110
HALF_W            equ 20
HSTEP             equ 8
MAX_H             equ 5
SEA_LEVEL         equ 1                 ; land below this is water
DIRT_H            equ 8
RAIL_H            equ 12                ; coaster track height above the ground

HEADER_H          equ 34
PANEL_Y           equ 590
BTN_X0            equ 8
BTN_Y             equ PANEL_Y + 8
BTN_W             equ 88
BTN_H             equ 44
BTN_STEP          equ 92
BTN_TEXT          equ 32                ; label offset inside a button
LINE1_Y           equ PANEL_Y + 58
LINE2_Y           equ PANEL_Y + 78
LINE3_Y           equ PANEL_Y + 98
BANNER_X          equ 260
BANNER_Y          equ 270

; ---- colours (DIB pixels are 0xRRGGBB; GDI text colours are 0xBBGGRR) ------
C_BG              equ 0x10161C
C_PANEL           equ 0x1E2530
C_ACCENT          equ 0xFFC107
C_BTN             equ 0x2A3442
C_BTN_SEL         equ 0x3D4F66
TXT_WHITE         equ 0xFFFFFF
TXT_YELLOW        equ 0x07C1FF
TXT_GREY          equ 0xC5BEB0
TXT_DIM           equ 0x8A8078
TXT_CYAN          equ 0xEADE80
TXT_RED           equ 0x5252FF
HANDY_SHIRT       equ 0x43A047
MECH_SHIRT        equ 0x1E63C8
SKIN              equ 0xF1C27D

; ---- map / simulation ------------------------------------------------------
MAP_W             equ 30
MAP_H             equ 16
MAP_SIZE          equ MAP_W * MAP_H
ENTRY_X           equ 0
ENTRY_Y           equ 8
START_TREES       equ 22

MAX_GUESTS        equ 128
TICK_MS           equ 100
TICKS_PER_DAY     equ 50
START_CASH        equ 2500
ADMISSION         equ 5
RIDE_TICKS        equ 8                 ; how long a guest is busy on a flat ride
BANKRUPT_LIMIT    equ -500
GOAL_GUESTS       equ 50
GOAL_DAY          equ 40

MAX_COASTERS      equ 8
TRAIN_CARS        equ 3
QUEASY_LIMIT      equ 40                ; guests this nauseous won't ride a coaster
TAME_EXCITEMENT   equ 40

MAX_HANDY         equ 16
HANDY_COST        equ 100
HANDY_WAGE        equ 10
SWEEP_TICKS       equ 4
MECH_COST         equ 150
MECH_WAGE         equ 15
FIX_TICKS         equ 25                ; how long a repair takes
BREAK_ODDS        equ 900               ; a flat ride breaks down about once per this many ticks
COASTER_BREAK_ODDS equ 500
MAX_PRICE         equ 40
NO_TARGET         equ 0xFFFF

; Tile types - index into every tile_* table
T_GRASS           equ 0
T_PATH            equ 1
T_ENTRANCE        equ 2
T_STATION         equ 3                 ; T_STATION..T_FOOD are attractions
T_FERRIS          equ 4
T_CAROUSEL        equ 5
T_FOOD            equ 6
T_TREE            equ 7
T_PUKE            equ 8
T_TRACK           equ 9

TOOL_COUNT        equ 12
TOOL_HANDY        equ 0xFE              ; tool_tile markers for tools that don't place a tile
TOOL_RAISE        equ 0xFD
TOOL_LOWER        equ 0xFC
TOOL_MECH         equ 0xFB
TOOL_RAISE_IDX    equ 7                 ; tool indices
TOOL_LOWER_IDX    equ 8
TOOL_HANDY_IDX    equ 9
TOOL_MECH_IDX     equ 10
TOOL_DEMOLISH     equ 11
TERRAFORM_COST    equ 20
START_HILLS       equ 3
START_LAKES       equ 2

; Guest record layout
G_ACTIVE          equ 0                 ; byte
G_X               equ 1                 ; byte
G_Y               equ 2                 ; byte
G_DIR             equ 3                 ; byte, 0=up 1=right 2=down 3=left
G_HAPPY           equ 4                 ; byte, 0-100
G_HUNGER          equ 5                 ; byte, 0-100
G_NAUSEA          equ 6                 ; byte, 0-100
G_COOL            equ 7                 ; byte, ticks left on current ride
G_CASH            equ 8                 ; dword
G_ID              equ 12                ; dword
G_LAST            equ 16                ; byte, tile type of last attraction
G_PX              equ 17                ; byte, position before the last tick (for smooth walking)
G_PY              equ 18                ; byte
GUEST_SIZE        equ 32

; Coaster record layout (rebuilt by analyze_coasters whenever the map changes)
CO_STATION        equ 0                 ; dword, map index of the station
CO_JOY            equ 4                 ; byte
CO_NAUSEA         equ 5                 ; byte
CO_LEN            equ 8                 ; dword, track tiles in the circuit
CO_TURNS          equ 12                ; dword
CO_EXCITE         equ 16                ; dword
CO_TICKET         equ 20                ; dword
CO_RUN            equ 24                ; dword, ticks the train keeps running
CO_TRAIN          equ 28                ; dword, lead car's position in the circuit
CO_PATH           equ 32                ; dword, circuit's first entry in circ
CO_MOVED          equ 36                ; dword, train advanced on the last tick
CO_DROPS          equ 40                ; dword, total levels the track falls per lap
CO_SPLASH         equ 44                ; dword, track tiles over water
CO_SIZE           equ 48

; Handyman record layout
H_ACTIVE          equ 0
H_X               equ 1
H_Y               equ 2
H_DIR             equ 3
H_BUSY            equ 4                 ; ticks left sweeping or repairing
H_PX              equ 5
H_PY              equ 6
H_TYPE            equ 7                 ; STAFF_HANDY or STAFF_MECH
H_TARGET          equ 8                 ; word, map index of the ride being repaired
HANDY_SIZE        equ 16

STAFF_HANDY       equ 0
STAFF_MECH        equ 1

; Sounds - index into the sound table in sound.asm
SND_BUILD         equ 0
SND_CASH          equ 1
SND_SCREAM        equ 2
SND_SPLAT         equ 3
SND_BREAK         equ 4
SND_FIXED         equ 5
SND_FANFARE       equ 6
SND_COUNT         equ 7
SND_AMBIENT       equ 0                 ; play_sound modes: skip if another sound is playing...
SND_NOW           equ 1                 ; ...or cut it off

; GameOver
GO_NONE           equ 0
GO_WIN            equ 1
GO_LOSE           equ 2
GO_BANKRUPT       equ 3

%macro PEN 1
    mov     dword [pen], %1
%endmacro

%macro BOX_PENS 3
    mov     dword [pen_top], %1
    mov     dword [pen_left], %2
    mov     dword [pen_right], %3
%endmacro
