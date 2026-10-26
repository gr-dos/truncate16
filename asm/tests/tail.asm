; tail - write the command tail to standard output
;
;   tail [ARGUMENTS]
;
; Test helper.  Writes the PSP command tail (the bytes after the
; program name, as the shell passed them) to standard output with no
; line ending, so the tests can check what reaches truncate.exe and
; truncate.com before either one splits it.
;
; Build: nasm -f bin -o tail.com tail.asm

        cpu     8086
        org     100h

start:
        mov     dx, 81h
        mov     cl, [80h]
        xor     ch, ch
        mov     bx, 1
        mov     ah, 40h                 ; write CX bytes at DX to handle 1
        int     21h
        mov     ax, 4C00h
        int     21h
