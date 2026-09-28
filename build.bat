@echo off
rem Assembles every module in src\ and links them into tycoon.exe.
call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat" >nul 2>nul
cd /d "%~dp0"
if not exist build mkdir build
for %%f in (src\*.asm) do (
    nasm -f win64 -I src\ -o build\%%~nf.obj %%f || exit /b 1
)
link /nologo /subsystem:windows /entry:mainCRTStartup /out:tycoon.exe build\*.obj ^
    libcmt.lib libvcruntime.lib libucrt.lib legacy_stdio_definitions.lib kernel32.lib user32.lib gdi32.lib
