; truncate - shrink or extend the size of a file to the specified size
;
; 8086 assembly version of truncate.c for MS-DOS, built as a .COM with
; NASM, using only DOS 2.0 calls.  truncate.c is the specification: the
; options, size arithmetic, messages and exit status are the same, and
; so are the parts of the Watcom C runtime that show through (argument
; splitting, errno and its messages, and how chsize extends a file).
;
; Build: nasm -f bin -DVERSION='"0.01"' -o truncate.com truncate.asm
;
; SPDX-License-Identifier: MIT

        cpu     8086
        org     100h

%ifndef VERSION
%define VERSION 'unknown'
%endif

STACK   equ     512
MAXARGS equ     64              ; the most a 127-byte command tail holds
ZEROS   equ     512             ; chsize writes zeros 512 bytes at a time

; errno values of the Watcom C runtime
ENOENT  equ     1
ENOSPC  equ     12

        section .text

start:
        cld
        mov     ax, sp
        sub     ax, STACK
        jc      nomem
        cmp     ax, bss_end
        jb      nomem
        mov     di, bss_start           ; DOS does not clear it
        mov     cx, bss_end - bss_start
        xor     al, al
        rep     stosb

        call    split

; First pass: options.  Each option, and the SIZE it takes, is replaced
; by 0 in argv; the files are counted.
        mov     bx, argv
.opt:   cmp     bx, [argv_end]
        jae     .optdone
        mov     si, [bx]
        cmp     byte [endopts], 0
        jne     .file
        cmp     byte [si], '-'
        jne     .file
        mov     al, [si + 1]
        test    al, al
        jz      .file
        mov     word [bx], 0
        cmp     al, '-'
        jne     .short
        cmp     byte [si + 2], 0
        jne     .long
        mov     byte [endopts], 1
        jmp     .next

.long:  mov     di, s_nocreate
        call    strcmp
        je      .nocreate
        push    si
        mov     di, s_size
        mov     cx, 6
        repe    cmpsb
        pop     si
        jne     .long2
        mov     al, [si + 6]
        test    al, al
        jz      .size_next
        cmp     al, '='
        jne     .long2
        add     si, 7
        jmp     .size
.size_next:
        call    next_arg
        jnc     .size
        mov     si, m_size_arg
        jmp     usage_error
.long2: mov     di, s_help
        call    strcmp
        je      help
        mov     di, s_version
        call    strcmp
        je      version
        mov     [arg], si
        mov     si, m_unrec
        jmp     usage_error

.short: inc     si
.letter:
        lodsb
        test    al, al
        jz      .next
        cmp     al, 'c'
        je      .c
        cmp     al, 's'
        je      .s
        cmp     al, 'h'
        je      help
        cmp     al, '?'
        je      help
        mov     [optchar], al
        mov     si, m_invalid
        jmp     usage_error
.c:     mov     byte [no_create], 1
        jmp     .letter
.s:     cmp     byte [si], 0            ; -sSIZE
        jne     .size
        call    next_arg                ; -s SIZE
        jnc     .size
        mov     si, m_s_arg
        jmp     usage_error

.nocreate:
        mov     byte [no_create], 1
        jmp     .next
.size:  call    parse_size              ; the rest of the word was SIZE
        mov     byte [have_size], 1
        jmp     .next
.file:  inc     word [nfiles]
.next:  inc     bx
        inc     bx
        jmp     .opt

.optdone:
        mov     si, m_nosize
        cmp     byte [have_size], 0
        je      usage_error
        mov     si, m_missing
        cmp     word [nfiles], 0
        je      usage_error

; Second pass: the files.
        mov     bx, argv
.each:  cmp     bx, [argv_end]
        jae     .done
        mov     si, [bx]
        test    si, si
        jz      .skip
        push    bx
        call    truncate_one
        pop     bx
.skip:  inc     bx
        inc     bx
        jmp     .each
.done:  mov     al, [status]
exit:   mov     ah, 4Ch
        int     21h

help:   mov     si, m_usage
        jmp     print_exit
version:
        mov     si, m_version
print_exit:
        mov     bx, 1
        call    write_str
        mov     al, 0
        jmp     exit

; Print the message at SI (see error), then the "Try" line, and exit 1.
usage_error:
        call    error
        mov     si, m_try
        mov     bx, 2
        call    write_str
fail:   mov     al, 1
        jmp     exit

nomem:  mov     dx, m_nomem
        mov     ah, 09h
        int     21h
        jmp     fail

;
; Split the command tail into argv the way the Open Watcom C startup
; does (found by testing its build; see asm/README.md):
;   - blanks (space, tab) separate arguments; leading ones are skipped;
;   - " toggles quoting and is removed; blanks inside quotes are kept;
;   - a lone \ before " makes it a literal " (the \ is dropped);
;   - a run of n >= 2 backslashes before " gives n - 1 backslashes and
;     a toggle (not the Microsoft parity rule);
;   - any other \ is literal.
; Only the byte before a \ that precedes " needs checking: every earlier
; \ in the run has already been copied as a literal.  AH holds it.
;
split:
        mov     si, 81h
        mov     cl, [80h]
        xor     ch, ch
        cmp     cl, 127
        jbe     .len
        mov     cl, 127
.len:   mov     di, argbuf
        mov     bx, argv
.skip:  jcxz    .done
        lodsb
        dec     cx
        cmp     al, ' '
        je      .skip
        cmp     al, 9
        je      .skip
        dec     si
        inc     cx
        mov     [bx], di
        inc     bx
        inc     bx
        xor     dl, dl                  ; DL = 1 inside quotes
        mov     al, ' '
.char:  jcxz    .end
        mov     ah, al
        lodsb
        dec     cx
        cmp     al, '\'
        jne     .notbs
        jcxz    .copy
        cmp     byte [si], '"'
        jne     .copy
        cmp     ah, '\'                 ; \\" : the " is a toggle
        je      .char
        movsb                           ; \"  : a literal "
        dec     cx
        mov     al, '"'
        jmp     .char
.notbs: cmp     al, '"'
        jne     .notq
        xor     dl, 1
        jmp     .char
.notq:  test    dl, dl
        jnz     .copy
        cmp     al, ' '
        je      .end
        cmp     al, 9
        je      .end
.copy:  stosb
        jmp     .char
.end:   mov     byte [di], 0
        inc     di
        jmp     .skip
.done:  mov     [argv_end], bx
        ret

; The argument after BX, for an option's SIZE: CF if there is none,
; otherwise BX moves to it, SI is it and its slot is cleared.
next_arg:
        lea     ax, [bx + 2]
        cmp     ax, [argv_end]
        cmc
        jc      .ret
        mov     bx, ax
        mov     si, [bx]
        mov     word [bx], 0
.ret:   ret

; ZF if the strings at SI and DI are the same.  Keeps SI.
strcmp: push    si
.l:     lodsb
        scasb
        jne     .ret
        test    al, al
        jnz     .l
.ret:   pop     si
        ret

;
; Parse the SIZE at SI into size_mod and size_val, as parse_size in
; truncate.c.  On an error, print it and exit 1.  Keeps BX.
;
parse_size:
        push    bx
        mov     [arg], si
        call    skip_blanks
        mov     byte [size_mod], 0
        mov     al, [si]
        mov     di, mods
        mov     cx, mods_len
        repne   scasb
        jne     .nomod
        mov     [size_mod], al
        inc     si
        call    skip_blanks
.nomod: mov     al, [si]
        sub     al, '0'
        cmp     al, 9
        ja      .invalid
        xor     ax, ax
        xor     dx, dx
.digit: mov     cl, [si]
        sub     cl, '0'
        cmp     cl, 9
        ja      .unit
        inc     si
        push    cx
        mov     bx, 10
        xor     cx, cx
        call    mul32
        pop     cx
        jc      .toolarge
        xor     ch, ch
        add     ax, cx
        adc     dx, 0
        js      .toolarge
        jmp     .digit

.unit:  mov     [size_val], ax
        mov     [size_val + 2], dx
        lodsb
        test    al, al
        jz      .check
        mov     di, units
        mov     cx, units_len
        repne   scasb
        jne     .invalid
        mov     bx, cx
        mov     cl, [unit_power + bx]
        mov     bx, 1024
        lodsb
        cmp     al, 'B'                 ; KB: powers of 1000
        jne     .notb
        mov     bx, 1000
        jmp     .end
.notb:  cmp     al, 'i'                 ; KiB: same as K
        jne     .end0
        lodsb
        cmp     al, 'B'
        jne     .invalid
.end:   lodsb
.end0:  test    al, al
        jnz     .invalid

        ; zero times any unit is zero, even one too large for a long
        mov     ax, [size_val]
        or      ax, [size_val + 2]
        jz      .check
        mov     ax, 1                   ; DX:AX = BX to the power CL
        xor     dx, dx
        xor     ch, ch
.pow:   push    cx
        xor     cx, cx
        call    mul32
        pop     cx
        jc      .toolarge
        loop    .pow
        mov     bx, ax
        mov     cx, dx
        mov     ax, [size_val]
        mov     dx, [size_val + 2]
        call    mul32
        jc      .toolarge
        mov     [size_val], ax
        mov     [size_val + 2], dx

.check: cmp     byte [size_mod], '/'
        je      .zero
        cmp     byte [size_mod], '%'
        jne     .ok
.zero:  mov     ax, [size_val]
        or      ax, [size_val + 2]
        jnz     .ok
        mov     si, m_divzero
        jmp     .error
.ok:    pop     bx
        ret
.invalid:
        mov     si, m_invalid_num
        jmp     .error
.toolarge:
        mov     si, m_too_large
.error: call    error
        jmp     fail

skip_blanks:
        cmp     byte [si], ' '
        je      .next
        cmp     byte [si], 9
        jne     .ret
.next:  inc     si
        jmp     skip_blanks
.ret:   ret

; DX:AX = DX:AX * CX:BX, for operands of at most 7FFFFFFFh.  CF if the
; product is over 7FFFFFFFh (LONG_MAX).  Keeps BX, CX and SI.
mul32:  push    bx
        push    cx
        push    si
        test    dx, dx
        jz      .small
        test    cx, cx
        jnz     .over
        xchg    ax, bx
        xchg    dx, cx
.small: mov     si, ax                  ; SI * CX:BX
        mul     cx
        test    dx, dx
        jnz     .over
        mov     cx, ax
        mov     ax, si
        mul     bx
        add     dx, cx
        jc      .over
        test    dx, dx                  ; clears CF
        jns     .ret
.over:  stc
.ret:   pop     si
        pop     cx
        pop     bx
        ret

; DX:AX = DX:AX mod CX:BX, unsigned, for a divisor of at most
; 7FFFFFFFh.  Keeps BX and CX.
umod:   push    si
        push    di
        push    bp
        xor     si, si                  ; SI:DI = remainder
        xor     di, di
        mov     bp, 32
.bit:   shl     ax, 1
        rcl     dx, 1
        rcl     di, 1
        rcl     si, 1
        cmp     si, cx
        jne     .cmp
        cmp     di, bx
.cmp:   jb      .next
        sub     di, bx
        sbb     si, cx
.next:  dec     bp
        jnz     .bit
        mov     ax, di
        mov     dx, si
        pop     bp
        pop     di
        pop     si
        ret

;
; Truncate or extend the file named at SI, as truncate_one in
; truncate.c.  On an error, print it and set status to 1.
;
truncate_one:
        mov     [arg], si
        mov     dx, si
        mov     ax, 3D02h               ; open for reading and writing
        int     21h
        jnc     .opened
        call    set_errno
        cmp     byte [no_create], 0
        jne     .nocreate
        cmp     ax, 2                   ; file not found: create it
        jne     .openfail
        mov     dx, [arg]
        xor     cx, cx
        mov     ah, 3Ch
        int     21h
        jnc     .opened
        call    set_errno
        jmp     .openfail
.nocreate:
        cmp     byte [errno], ENOENT    ; -c: a missing file is no error
        je      .ret
.openfail:
        mov     si, m_open
        call    error
        jmp     .status

.opened:
        mov     [handle], ax
        mov     bx, ax
        mov     ax, 4202h               ; filelength
        xor     cx, cx
        xor     dx, dx
        int     21h
        jc      .sizeerr
        test    dx, dx                  ; 2 GiB or more is a negative
        js      .sizefail               ; long, so an error with errno
        mov     [fsize], ax             ; as it was
        mov     [fsize + 2], dx

        call    new_size
        jc      .overflow
        mov     [nsize], ax
        mov     [nsize + 2], dx
        cmp     ax, [fsize]
        jne     .chsize
        cmp     dx, [fsize + 2]
        je      .close

        ; chsize: the file position is at the end
.chsize:
        mov     bx, [handle]
        sub     ax, [fsize]
        sbb     dx, [fsize + 2]
        js      .shrink
        mov     di, ax                  ; extend by SI:DI zero bytes
        mov     si, dx
.ext:   mov     cx, ZEROS
        test    si, si
        jnz     .write
        cmp     di, cx
        jae     .write
        mov     cx, di
.write: mov     dx, zeros
        mov     ah, 40h
        int     21h
        jc      .nospace
        cmp     ax, cx
        jne     .nospace
        sub     di, cx
        sbb     si, 0
        mov     ax, di
        or      ax, si
        jnz     .ext
        jmp     .close
.nospace:
        mov     byte [errno], ENOSPC    ; whatever DOS said
        jmp     .truncfail
.shrink:
        mov     dx, [nsize]             ; seek to the new size and
        mov     cx, [nsize + 2]         ; write nothing there
        mov     ax, 4200h
        int     21h
        jc      .truncerr
        xor     cx, cx
        mov     ah, 40h
        int     21h
        jnc     .close
.truncerr:
        call    set_errno
.truncfail:
        mov     si, m_truncate
        jmp     .fail

.close: mov     bx, [handle]
        mov     ah, 3Eh
        int     21h
        jnc     .ret
        call    set_errno
        mov     si, m_close
        call    error
        jmp     .status

.sizeerr:
        call    set_errno
.sizefail:
        mov     si, m_getsize
        jmp     .fail
.overflow:
        mov     si, m_overflow
.fail:  call    error
        mov     bx, [handle]
        mov     ah, 3Eh
        int     21h
        jnc     .status
        call    set_errno
.status:
        mov     byte [status], 1
.ret:   ret

; The new size of a file fsize bytes long in DX:AX, as new_size in
; truncate.c; CF on overflow.  fsize is at most 7FFFFFFFh.
new_size:
        mov     ax, [fsize]
        mov     dx, [fsize + 2]
        mov     bx, [size_val]
        mov     cx, [size_val + 2]
        mov     al, [size_mod]
        cmp     al, '+'
        je      .extend
        cmp     al, '-'
        je      .reduce
        cmp     al, '<'
        je      .atmost
        cmp     al, '>'
        je      .atleast
        cmp     al, '/'
        je      .rounddn
        cmp     al, '%'
        je      .roundup
.size:  mov     ax, bx                  ; set to
        mov     dx, cx
        clc
        ret
.extend:
        mov     ax, [fsize]
        add     ax, bx
        adc     dx, cx
.sign:  mov     bx, dx                  ; CF if over 7FFFFFFFh
        shl     bx, 1
        ret
.reduce:                                ; not below 0
        mov     ax, [fsize]
        sub     ax, bx
        sbb     dx, cx
        jnc     .ret
        xor     ax, ax
        cwd
.ret:   ret
.atmost:
        mov     ax, [fsize]
        cmp     dx, cx
        jne     .am
        cmp     ax, bx
.am:    jb      .keep
        jmp     .size
.atleast:
        mov     ax, [fsize]
        cmp     dx, cx
        jne     .al
        cmp     ax, bx
.al:    jbe     .size
.keep:  clc
        ret
.rounddn:                               ; fsize - fsize % size_val
        mov     ax, [fsize]
        call    umod
        mov     bx, ax
        mov     cx, dx
        mov     ax, [fsize]
        mov     dx, [fsize + 2]
        sub     ax, bx
        sbb     dx, cx
        ret
.roundup:                               ; fsize - r + size_val, r != 0
        mov     ax, [fsize]
        call    umod
        mov     bx, ax
        or      bx, dx
        jz      .unchanged
        mov     bx, ax
        mov     cx, dx
        mov     ax, [fsize]
        mov     dx, [fsize + 2]
        sub     ax, bx
        sbb     dx, cx
        add     ax, [size_val]
        adc     dx, [size_val + 2]
        jmp     .sign
.unchanged:
        mov     ax, [fsize]
        mov     dx, [fsize + 2]         ; CF is clear from or
        ret

; Store the errno the Watcom runtime would set for DOS error AX.
; Keeps AX.
set_errno:
        push    bx
        cmp     ax, 50h
        mov     bl, 7                   ; EEXIST
        je      .set
        mov     bl, -1
        cmp     ax, doserr_len
        jae     .set
        mov     bx, ax
        mov     bl, [doserr + bx]
.set:   mov     [errno], bl
        pop     bx
        ret

;
; Print "truncate: " and the message at SI on standard error.  In the
; message, byte 1 stands for the argument [arg], 2 for strerror(errno),
; 3 for [nsize] in decimal and 4 for the character [optchar].
;
error:  mov     word [lbp], linebuf
        push    si
        mov     si, m_prog
        call    lb_add
        pop     si
.fmt:   lodsb
        test    al, al
        jz      .flush
        cmp     al, 4
        ja      .char
        push    si
        cmp     al, 2
        jb      .arg
        je      .errno
        cmp     al, 3
        je      .dec
        mov     al, [optchar]
        call    lb_addc
        jmp     .done
.arg:   mov     si, [arg]
        call    lb_add
        jmp     .done
.errno: call    strerror
        call    lb_add
        jmp     .done
.dec:   mov     ax, [nsize]
        mov     dx, [nsize + 2]
        call    lb_dec
.done:  pop     si
        jmp     .fmt
.char:  call    lb_addc
        jmp     .fmt
.flush: mov     si, [lbp]
        mov     byte [si], 0
        mov     si, linebuf
        mov     bx, 2
        jmp     write_str

; SI = the message for errno.
strerror:
        mov     al, [errno]
        mov     si, errors
.l:     cmp     byte [si], -1           ; the last one: unknown
        je      .found
        cmp     [si], al
        je      .found
.skip:  inc     si
        cmp     byte [si], 0
        jne     .skip
        inc     si
        jmp     .l
.found: inc     si
        ret

; Append SI to the line buffer.
lb_add: lodsb
        test    al, al
        jz      .ret
        call    lb_addc
        jmp     lb_add
.ret:   ret

; Append AL.
lb_addc:
        push    di
        mov     di, [lbp]
        stosb
        mov     [lbp], di
        pop     di
        ret

; Append DX:AX in decimal.
lb_dec: mov     bx, 10
        xor     cx, cx
.div:   mov     si, ax
        mov     ax, dx
        xor     dx, dx
        div     bx
        xchg    ax, si
        div     bx
        push    dx                      ; the next digit, from the right
        inc     cx
        mov     dx, si
        mov     si, ax
        or      si, dx
        jnz     .div
.out:   pop     ax
        add     al, '0'
        call    lb_addc
        loop    .out
        ret

; Write SI to handle BX, with each \n written as CR LF.
write_str:
        mov     dx, si
.scan:  lodsb
        test    al, al
        jz      .last
        cmp     al, 10
        jne     .scan
        push    si
        mov     cx, si
        dec     cx
        sub     cx, dx
        call    write
        mov     dx, crlf
        mov     cx, 2
        call    write
        pop     si
        jmp     write_str
.last:  mov     cx, si
        dec     cx
        sub     cx, dx
write:  jcxz    .ret                    ; CX bytes at DX to handle BX
        mov     ah, 40h
        int     21h
.ret:   ret

        section .data

; errno for DOS errors 0 to 21h, as the Watcom runtime maps them
; (-1 is its "unknown error")
doserr: db      0, 9, 1, 1, 11, 6, 4, 5, 5, 5, 2, 3, -1, 14, 7, 36
        db      6, 8, 1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1
        db      6, 6
doserr_len equ  $ - doserr

; strerror for each errno above: the errno, then the message
errors: db      0, 'No error', 0
        db      1, 'No such file or directory', 0
        db      2, 'Arg list too big', 0
        db      3, 'Exec format error', 0
        db      4, 'Bad file number', 0
        db      5, 'Not enough memory', 0
        db      6, 'Permission denied', 0
        db      7, 'File exists', 0
        db      8, 'Cross-device link', 0
        db      9, 'Invalid argument', 0
        db      11, 'Too many open files', 0
        db      12, 'No space left on device', 0
        db      14, 'Result too large', 0
        db      36, 'No such device', 0
        db      -1, 'unknown error', 0

; size modifiers, and units with their powers (indexed from the end)
mods:   db      '+-<>/%'
mods_len equ    $ - mods
units:  db      'kKmMgGtTPEZYRQ'
units_len equ   $ - units
unit_power:
        db      10, 9, 8, 7, 6, 5, 4, 4, 3, 3, 2, 2, 1, 1

s_nocreate:
        db      '--no-create', 0
s_size: db      '--size'
s_help: db      '--help', 0
s_version:
        db      '--version', 0

crlf:   db      13, 10

m_usage:
        db      'Usage: truncate OPTION... FILE...', 10
        db      'Shrink or extend the size of each FILE to the specified size.', 10
        db      10
        db      'A FILE argument that does not exist is created.', 10
        db      10
        db      'If a FILE is larger than the specified size, the extra data is lost.', 10
        db      'If a FILE is shorter, it is extended and the extended part reads', 10
        db      'as zero bytes.', 10
        db      10
        db      '  -c, --no-create        do not create any files', 10
        db      '  -s, --size=SIZE        set or adjust the file size by SIZE bytes', 10
        db      '  -h, --help             display this help and exit', 10
        db      '      --version          output version information and exit', 10
        db      10
        db      'SIZE is an integer and optional unit (example: 10K is 10*1024).', 10
        db      'Units are K,M,G (powers of 1024) or KB,MB,GB (powers of 1000).', 10
        db      'Binary prefixes can be used, too: KiB=K, MiB=M, and so on.', 10
        db      10
        db      'SIZE may also be prefixed by one of the following modifying characters:', 10
        db      "'+' extend by, '-' reduce by, '<' at most, '>' at least,", 10
        db      "'/' round down to multiple of, '%' round up to multiple of.", 10, 0

m_version:
        db      'truncate (dos-truncate16) ', VERSION, 10, 0

m_try:  db      "Try 'truncate --help' for more information.", 10, 0
m_prog: db      'truncate: ', 0
m_size_arg:
        db      "option '--size' requires an argument", 10, 0
m_s_arg:
        db      "option requires an argument -- 's'", 10, 0
m_unrec:
        db      "unrecognized option '", 1, "'", 10, 0
m_invalid:
        db      "invalid option -- '", 4, "'", 10, 0
m_nosize:
        db      "you must specify '--size'", 10, 0
m_missing:
        db      'missing file operand', 10, 0
m_invalid_num:
        db      "Invalid number: '", 1, "'", 10, 0
m_too_large:
        db      "Invalid number: '", 1, "': Value too large", 10, 0
m_divzero:
        db      'division by zero', 10, 0
m_open: db      "cannot open '", 1, "' for writing: ", 2, 10, 0
m_getsize:
        db      "cannot get the size of '", 1, "': ", 2, 10, 0
m_overflow:
        db      "overflow extending size of file '", 1, "'", 10, 0
m_truncate:
        db      "failed to truncate '", 1, "' at ", 3, ' bytes: ', 2, 10, 0
m_close:
        db      "failed to close '", 1, "': ", 2, 10, 0
m_nomem:
        db      'truncate: not enough memory', 13, 10, '$'

        section .bss

bss_start:
errno:          resb    1
status:         resb    1
no_create:      resb    1
endopts:        resb    1
have_size:      resb    1
size_mod:       resb    1
optchar:        resb    1
                resb    1
nfiles:         resw    1
size_val:       resd    1
fsize:          resd    1
nsize:          resd    1
handle:         resw    1
arg:            resw    1
lbp:            resw    1
argv_end:       resw    1
argv:           resw    MAXARGS
argbuf:         resb    128
linebuf:        resb    256
zeros:          resb    ZEROS
bss_end:
