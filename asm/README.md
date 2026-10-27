# truncate.com: 8086 assembly version

`truncate.asm` is a hand-written 8086 assembly version of `truncate`,
built as a `.COM` with NASM. It is an experiment
([#2](https://github.com/gr-dos/truncate16/issues/2)) to see how much
smaller `truncate` gets without a C runtime, and what it costs
to keep two implementations in step. It follows the "C reference and
assembly" layout of [hello16](https://github.com/gr-dos/hello16).

`truncate.c` stays the reference. The top-level `make` and `make test`
still build and test only the C `truncate.exe`. CI and the release
workflow also run `make -C asm test`, so the two versions cannot drift
apart unnoticed, and each release ships `truncate.com` alongside
`truncate.exe`.

## Build and test

Needs NASM (any 2.x or 3.x; checked with 3.01). The tests also need
DOSBox-X, mtools and what the top-level build needs for the reference
`truncate.exe` (libc16 and its Open Watcom, fetched by `make`).

    make -C asm                  # truncate.com
    make -C asm test             # existing suite + differential tests
    make -C asm measure          # size / FAT12 / memory comparison
    make -C asm clean

    make -C asm test DOSBOX=$PWD/asm/tests/dosbox-8086   # on an 8086

`LIBC16_ROOT=` works as it does at the top level, and is passed down when
the reference `truncate.exe` needs building. The build is one command,

    nasm -f bin -Werror '-DVERSION="0.01"' -o truncate.com truncate.asm

NASM's flat binary output is deterministic, so the same source and
`VERSION` always give the same bytes. The source starts with `cpu 8086`,
so NASM rejects any instruction newer than the original 8086.

`make -C asm test` runs:

- `tests/run.sh`, the existing suite (unchanged, 132 checks), on
  `truncate.com`. The suite copies the program to `truncate.exe`. DOS
  chooses between EXE and COM by the `MZ` signature, not the name, so
  the image still runs as a COM.
- `tests/diff.sh`, which runs `truncate.exe` and `truncate.com` on the
  same 180 argument lists, each in its own copy of the same fixtures.
  It requires identical bytes on standard output, identical bytes on
  standard output plus standard error, identical exit status, and
  identical files left behind (names, sizes and contents, in the
  directory and on a floppy image). The cases run five times: the
  reference and `truncate.com` with both streams captured, both with
  standard output only, and `truncate.com` again with DOS reporting
  version 2.11. Seven outputs are also checked against exact expected
  bytes, CR LF included. That makes 1,277 checks.

The 180 lists cover what `run.sh` does not:

- option parsing: every diagnostic, options before and after files,
  `--` and `-`, repeated `-s` (the last wins, but a bad one fails),
  `--size=` with nothing after it, near misses such as `--siz=5`,
  `--sizex=5` and `--HELP`, and `--help` or `--version` before or after
  a bad option;
- SIZE parsing: blanks around the prefix, double prefixes, every unit
  letter in upper and lower case, `B`, `iB` and bad suffixes, leading
  zeros, values just over 2 GiB − 1 with and without units, zero with
  units too large for a long, and `/0` or `%0K`;
- each modifier at its edges (`+0`, `-0`, `<0`, `>0`, `/1`, `%1`,
  sizes already a multiple, and reducing by more than the size);
- files: read-only files (with and without `-c`), directories (`sub`,
  `.`, `..`), forward slashes, a trailing `\`, a missing directory, an
  invalid drive (with `-c` it is silently skipped, as in C), an empty
  name, the `NUL` device, a long name cut to 8.3, the same file twice,
  and 52 arguments, close to the most a command line holds;
- the 2 GiB limit: overflow with `+` and `%`, shrinking 2 GiB − 1
  files, and a 3 GiB file, which the C version cannot size;
- a disk that fills while a file is extended (`No space left on
  device`), on a 360 KB floppy image;
- runs of 0 to 8 backslashes before a quote, as in hello16, and other
  quoting.

Standard error is captured with `tests/err2out.asm`, which runs a
program with handle 2 duplicated from handle 1, because DOS shells
cannot redirect it. `tests/tail.asm` writes back the command tail it is
given, to check that the shell passes each list through unchanged. Both
helpers come from hello16.

The harness does catch differences. A build that differs only in the
`--version` text and one `strerror` message fails 12 checks.

`tests/dosbox-8086` runs DOSBox-X with `cputype=8086`, where an 80186
instruction does not run as one. Both suites pass there for both
programs. DOSBox-X calls this CPU mode experimental.

## Results

From `make -C asm measure` (libc16 and the Open Watcom snapshot it
pins, NASM 3.01, `VERSION` 0.01):

| | `truncate.exe` (C, libc16) | `truncate.com` (asm) |
|---|---:|---:|
| File size | 5,686 bytes | 3,294 bytes (1,531 code, 1,763 data) |
| 360K / 720K floppy (1 KB clusters) | 6 clusters, 6,144 bytes | 4 clusters, 4,096 bytes |
| 1.2M / 1.44M floppy (512 B clusters) | 12 clusters, 6,144 bytes | 7 clusters, 3,584 bytes |
| Conventional memory to run | 8,272 bytes | 5,118 bytes |
| DOS version | 2.0 or later | 2.0 or later |
| CPU | 8086 | 8086 |

The `.COM` is 42% smaller and saves 2 KB (2 clusters) on a 360 KB
floppy. Of its 1,763 bytes of data, 903 are the `--help` text and 241
are the `strerror` messages. With Open Watcom's own C runtime, before
libc16, `truncate.exe` was 16,184 bytes and needed 19,008 bytes of
memory.

FAT figures are measured: each file is copied onto a freshly formatted
image with mtools, and the drop in free space is recorded.

Memory: the `truncate.exe` figure comes from the MZ header (PSP 256 +
load image 5,638 + minimum allocation 148 paragraphs, which holds BSS
and the stack). For `truncate.com` it is PSP 256 + image 3,294 +
1,056 bytes of uninitialised data (variables, the split arguments, a
message buffer and the 512 zero bytes written when extending) + a
512-byte stack. The program checks at startup that this fits below its
stack pointer. If it does not, it prints `truncate: not enough memory`
and exits with status 1. As for any `.COM`, DOS gives the program the
largest free block while it runs. That costs nothing for a utility that
does not stay resident or start another program.

DOS versions: the program uses only DOS 2.0 functions (09h, 3Ch, 3Dh,
3Eh, 40h, 42h and 4Ch) and the PSP command tail. The second
`truncate.com` phase of `diff.sh` runs with DOSBox-X reporting
DOS 2.11. DOSBox-X still provides its later functions when it does, so
this checks only that nothing refuses to run on version 2. The program
has not been run on a real DOS 2.x.

## How it matches the C version

The assembly is a separate implementation, written from `truncate.c`
and from testing the C build. It contains no C runtime code. Where the
C program's behaviour comes from its runtime, libc16, the assembly
follows libc16's specs (its `docs/spec/`):

- **Argument splitting:** the rules found for hello16 (blanks separate,
  `"` toggles and is removed, `\"` is a literal quote, and n ≥ 2
  backslashes before `"` give n − 1 backslashes and a toggle).
- **`open`:** open for read/write (3D02h). If that fails with "file not
  found" and `-c` was not given, create the file (3Ch). A successful
  create leaves `errno` as it was.
- **`errno`:** a single global value that nothing clears. DOS errors map
  to the same `errno` values as in libc16 (its `docs/spec/io.md`), and
  `strerror` gives libc16's text for each. This shows up in one place: `filelength`
  reports a file of 2 GiB or more as a negative size, and the C version
  then prints `cannot get the size of 'F': ` followed by whatever
  `errno` was left by an earlier file (`No error` if none). The
  assembly does the same.
- **`chsize`:** to extend, write zeros at the end of the file, 512
  bytes at a time. If a write is short, as on a full disk, the error is
  ENOSPC and the file stays partly extended; a failed write maps the DOS
  error as above. To shrink,
  seek to the new size and write 0 bytes.
- **Output:** `\n` is written as CR LF on both streams, as libc16's
  text-mode streams do. Both write each message to DOS directly; libc16's
  streams are unbuffered. Only `--help` and
  `--version` write to standard output, and they write nothing to
  standard error, so the bytes in each stream are the same.

Known differences and gaps:

- **Out of memory:** with less than about 5 KB free, the C version
  cannot load and DOS reports the error. The assembly version loads,
  then prints its own message and exits with status 1.
- **Write errors while extending:** only a full disk (a short write) is
  tested. A write-protected or failing disk is not covered.
- **Standard error ordering** on the screen is not an issue, because
  no run writes to both streams.

## Maintenance cost

`truncate.asm` is 927 lines (about 560 instructions), against 321 lines
of C. Most of the extra work goes into what C gets free: 32-bit
multiply and modulo on a 16-bit CPU, decimal output, a small message
formatter, argument splitting, and copies of libc16's `errno` table
and messages. Every change in behaviour has to be made twice, and
the assembly is harder to review. `tests/diff.sh` reduces the risk:
any difference in output, exit status or resulting files for its 180
cases fails CI. Still, a new feature needs its code written twice and
new comparison cases.

`truncate`'s behaviour is small and settled (it follows GNU coreutils),
so changes should be rare.

## Provenance and license

`truncate.asm`, `measure.sh` and `tests/diff.sh` were written for this
repository. `tests/err2out.asm`, `tests/tail.asm` and
`tests/dosbox-8086` are copied from
[hello16](https://github.com/gr-dos/hello16) (MIT). Nothing here is
derived from Open Watcom source. The first version copied runtime
behaviour found by black-box testing of the Open Watcom build; it now
follows libc16's specs and its tests. It is all
MIT licensed like the rest of the repository (see `../LICENSE`).

## Recommendation

**Keep the experiment, and ship `truncate.com` in GR-DOS** in place of
`truncate.exe` where floppy space matters. It is 42% smaller (3.2 KB
against 5.6 KB, 4 clusters against 6 on a 360 KB floppy), needs about
60% of the memory, and matches the C version on every case tested.

Keep `truncate.c` as the reference and default build. Releases attach
`asm/truncate.com` next to `truncate.exe` (from 0.02), after
`make -C asm test` passes, as hello16 does. The rule from hello16
applies: a PR that
changes `truncate.c` changes `asm/truncate.asm` in the same PR and adds
`diff.sh` cases.

The alternative in the issue, a slimmer C runtime (`libc16`, linked one
function per object), would keep a single source. It cannot get below
this baseline, though, since the program logic and messages alone are
about 3 KB. `make -C asm measure` gave `libc16` a target: 3,314 bytes
and 4 clusters. `truncate.exe` now links libc16 and is 5,686 bytes and
6 clusters, two clusters from the target (16,184 bytes and 16 clusters
with Open Watcom's runtime). That is the margin this section set for
retiring `truncate.asm`; whether to do so is left to a separate
decision.
