#!/bin/sh
#
# Differential tests: run the C truncate.exe and the assembly
# truncate.com on the same arguments, each in its own copy of the same
# fixtures, under DOSBox-X.  They must give identical bytes on standard
# output, identical bytes on standard output plus standard error,
# identical exit status, and leave identical files behind.  A few cases
# are also checked against exact expected bytes, CR LF endings
# included.
#
# The cases run five times, each in a fresh copy of the fixtures:
#
#   phase  program        captures                     DOS version
#   c      truncate.exe   standard output and error    default
#   a      truncate.com   standard output and error    default
#   co     truncate.exe   standard output              default
#   ao     truncate.com   standard output              default
#   a2     truncate.com   standard output and error    2.11
#
# DOS reporting 2.11 checks only for version gating: DOSBox-X still
# provides its later functions.
#
# Standard error is captured with err2out.com (built from err2out.asm
# next to this script), which runs a program with handle 2 duplicated
# from handle 1.  Each case also runs tail.com (from tail.asm), which
# writes the command tail it was given, to check that the shell passes
# the argument text through unchanged.  Redirections are written
# before the command (">file cmd args") so that arguments with an odd
# number of quotes do not swallow them.
#
# Fixtures, in each phase's directory and on its floppy (A:):
#
#   F10A.DAT ... F10I.DAT        10 bytes
#   F1000A.DAT ... F1000J.DAT    1000 bytes
#   RO.DAT                       200 bytes, read-only
#   SUB\                         an empty directory
#   BIG1.DAT BIGS.DAT BIGK.DAT   2147483647 bytes (sparse on the host)
#   BIG2.DAT                     2147483000 bytes
#   BIG3G.DAT                    3221225472 bytes, too big for a long
#   A:\EX.DAT                    3 bytes on a 360 KB floppy image
#
# To add a test: add a line to the case list below (the line is the
# argument text, verbatim; an empty line means no arguments).  Name a
# file no other case uses, so a difference shows up in that file.
#
# Usage: tests/diff.sh path/to/truncate.exe path/to/truncate.com
# Environment: DOSBOX (default dosbox-x), KEEP=1 to keep the work
#              directory.

set -u

here=$(cd "$(dirname "$0")" && pwd)
ref=${1:?usage: diff.sh truncate.exe truncate.com}
asm=${2:?usage: diff.sh truncate.exe truncate.com}
DOSBOX=${DOSBOX:-dosbox-x}

command -v "$DOSBOX" >/dev/null || { echo "$DOSBOX not found" >&2; exit 2; }
for t in mformat mcopy; do
    command -v $t >/dev/null || { echo "$t (mtools) not found" >&2; exit 2; }
done
for f in "$ref" "$asm" "$here/err2out.com" "$here/tail.com"; do
    [ -f "$f" ] || { echo "$f not found" >&2; exit 2; }
done
ref=$(cd "$(dirname "$ref")" && pwd)/$(basename "$ref")
asm=$(cd "$(dirname "$asm")" && pwd)/$(basename "$asm")

work=$(mktemp -d "${TMPDIR:-/tmp}/dostrunc.XXXXXX")
pass=0
fail=0
LC_ALL=C
export LC_ALL

phases="c a co ao a2"

# ------------------------------------------------------------------
# cases

cd "$work" || exit 2
cp "$ref" ref.exe &&
cp "$asm" asm.com &&
cp "$here/err2out.com" err2out.com &&
cp "$here/tail.com" tail.com || exit 2

tab=$(printf '\t')
many=$(printf ' a%.0s' $(seq 1 50))   # fits after "err2out asm.com"

cat > cases.txt <<EOS

-s
--size
-s 5
x.dat
--bogus -s 5 x.dat
-x
-cx
-s5 -q
--no-create=1 -s 5 x.dat
--sizex=5 x.dat
--siz=5 x.dat
--size= x.dat
--help --bogus
--bogus --help
-h --bogus
-s 5x --help
--help -s 5x
--version
--version x.dat
--help
-?
-h
--HELP
-ch
-Z
-s -5
-s 5 --
-- -s 5
-s 1 -s 2 n01.dat
-s 2 -s 9z n02.dat
-s "" n03.dat
-s " 5" n04.dat
-s "+ 5" f10a.dat
-s "$tab-$tab 3" f10b.dat
-s "5 " n05.dat
-s +-5 n06.dat
-s ++5 n06.dat
-s 1k n07.dat
-s 1kB n08.dat
-s 1kiB n09.dat
-s 1KIB n10.dat
-s 1kb n11.dat
-s 1p n12.dat
-s 0P n13.dat
-s 1P n14.dat
-s 1B n15.dat
-s 1iB n16.dat
-s 1KiBx n17.dat
-s 1Ki n18.dat
-s 2048M n19.dat
-s 2097152K n20.dat
-s 2147484KB n21.dat
-s 99999999999 n22.dat
-s 21474836470 n23.dat
-s 2147483648 n24.dat
-s 0000000000000000000000000005 n25.dat
-s 0x10 n26.dat
-s 1.5K n27.dat
-s -0 n28.dat
-s /0 n29.dat
-s %0K n30.dat
-s /0Q n31.dat
-s "/ 0" n32.dat
-s 1m n33.dat
-s 0Q n34.dat
-s 0RB n35.dat
-s 1Y n36.dat
-s 1T n37.dat
-s 2G n38.dat
-s "<1G" f10c.dat
-s ">1K" f10d.dat
-s +0 f10e.dat
-s -0 f10f.dat
-s "<0" f10g.dat
-s ">0" f10h.dat
-s /1 f1000a.dat
-s %1 f1000b.dat
-s /7 f1000c.dat
-s %7 f1000d.dat
-s %1000 f1000e.dat
-s /1000 f1000f.dat
-s /3K f1000g.dat
-s %3K f1000h.dat
-s -999 f1000i.dat
-s -1001 f1000j.dat
-s 5 ro.dat
-s ">5" ro.dat
-c -s 5 ro.dat
-s 5 sub
-s 5 .
-s 5 ..
-s 5 sub\\new.dat
-s 5 sub/new2.dat
-s 5 sub\\
-c -s 5 nofile.dat
-c -s 5 nodir\\x.dat
-c -s 5 q:\\x.dat
-s 5 q:\\x.dat
-s 5 nodir\\x.dat
-s 5 ""
-c -s 5 ""
-s 0 nul
-s 5 nul
-s +1 big1.dat
-s %2000000000 big2.dat
-s 5 big3g.dat
-s 5 nodir\\x.dat big3g.dat
-s 5 n40.dat big3g.dat
-s 5 ro.dat big3g.dat
-s "<2047M" bigs.dat
-s 2147483KB bigk.dat
-s 5 longfilename.dat
-s 6 n41.dat -c n42.dat f10i.dat
-s 3 n43.dat n43.dat
-s1$many
-s 1M a:\\full.dat
-s +400K a:\\ex.dat
-s 10 a:\\full.dat
"-s" 5 q01.dat
-"s" 5 q02.dat
"--size=5" q03.dat
-s 5 "q 04.dat"
-s "a b"
-s a"b c"d
-s a\\"b
EOS

# Runs of 0 to 8 backslashes before a quote, as SIZE (which every
# diagnostic echoes): mid-word with a quoted blank after, inside quotes
# before a blank, trailing, leading, closing a quoted argument, and in
# an option.
i=0
while [ $i -le 8 ]; do
    b=$(printf "%${i}s" '' | tr ' ' '\\')
    printf -- '-s %s\n' "a$b\"b c\"" "\"a$b\" b\"" "a$b\"" "$b\"x y" \
        "\"a b$b\"" "-$b\"h\"" >> cases.txt
    i=$((i + 1))
done

# ------------------------------------------------------------------
# fixtures

# mkfile NAME SIZE: SIZE bytes of a repeating, non-zero pattern
mkfile() {
    yes 'abcdefghijklmnopqrstuvwxyz0123456789' | head -c "$2" > "$1"
}

for p in $phases; do
    d=P$(echo $p | tr a-z A-Z)
    mkdir -p "$d/SUB" "OUT/$d" || exit 2
    for x in A B C D E F G H I; do mkfile "$d/F10$x.DAT" 10; done
    for x in A B C D E F G H I J; do mkfile "$d/F1000$x.DAT" 1000; done
    mkfile "$d/RO.DAT" 200
    chmod 444 "$d/RO.DAT"
    for x in BIG1 BIGS BIGK; do truncate -s 2147483647 "$d/$x.DAT"; done
    truncate -s 2147483000 "$d/BIG2.DAT"
    truncate -s 3221225472 "$d/BIG3G.DAT"
    mformat -C -f 360 -i "$d.IMG" :: || exit 2
    printf 'abc' > ex.dat
    mcopy -i "$d.IMG" ex.dat ::EX.DAT || exit 2
done
rm -f ex.dat

# ------------------------------------------------------------------
# the batch file

cat > rc.bat <<'EOS'
@echo off
if errorlevel 2 goto rc2
if errorlevel 1 goto rc1
echo rc0 >%1
goto end
:rc1
echo rc1 >%1
goto end
:rc2
echo rc2 >%1
:end
EOS

# for case N, in OUT\P<phase>:
#   ON.TXT  the output (both streams, or standard output only)
#   RN.TXT  the exit status
# and in OUT, TN.TXT: the command tail as tail.com received it
{
    printf '@echo off\r\n'
    n=0
    while IFS= read -r args; do
        n=$((n + 1))
        printf '>c:\\out\\t%d.txt c:\\tail %s\r\n' $n "$args"
    done < cases.txt
    for p in $phases; do
        d=p$p
        case $p in
        c|co) prog=c:\\ref.exe ;;
        *)    prog=c:\\asm.com ;;
        esac
        case $p in
        co|ao) run=$prog ;;
        *)     run="c:\\err2out $prog" ;;
        esac
        [ $p = a2 ] && printf 'ver set 2 11\r\n'
        printf 'imgmount -u a >nul\r\n'
        printf 'imgmount a c:\\%s.img -t floppy >nul\r\n' $d
        printf 'cd \\%s\r\n' $d
        n=0
        while IFS= read -r args; do
            n=$((n + 1))
            printf '>c:\\out\\%s\\o%d.txt %s %s\r\n' $d $n "$run" "$args"
            printf 'call c:\\rc c:\\out\\%s\\r%d.txt\r\n' $d $n
        done < cases.txt
        printf 'cd \\\r\n'
    done
} | sed 's/%/%%/g' > steps.bat           # % is special in batch files

SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy timeout 900 \
    "$DOSBOX" -defaultconf -silent -nogui -nomenu \
    -set "cpu cycles=max" \
    -c "mount c \"$work\"" -c "c:" \
    -c "steps.bat" -c "exit" >dosbox.log 2>&1

# ------------------------------------------------------------------
# checks

ok()     { pass=$((pass + 1)); }
not_ok() { printf "FAIL: %s\n" "$*"; fail=$((fail + 1)); }

# same REF TEST WHAT: files REF and TEST must exist and match
same() {
    if [ -f "$1" ] && [ -f "$2" ] && cmp -s "$1" "$2"; then
        ok
    else
        not_ok "$3: [$args]"
        diff "$1" "$2" 2>&1 | sed 's/^/    /'
    fi
}

n=0
while IFS= read -r args; do
    n=$((n + 1))
    if [ -n "$args" ]; then
        printf ' %s' "$args" > want.txt
    else
        : > want.txt
    fi
    if cmp -s want.txt "OUT/T$n.TXT"; then
        ok
    else
        not_ok "command tail for case $n is not [ $args]"
        od -c "OUT/T$n.TXT" 2>&1 | sed 's/^/    /'
    fi
    for t in PA PA2; do
        same OUT/PC/O$n.TXT OUT/$t/O$n.TXT "case $n output differs in $t"
        same OUT/PC/R$n.TXT OUT/$t/R$n.TXT "case $n exit status differs in $t"
    done
    same OUT/PCO/O$n.TXT OUT/PAO/O$n.TXT "case $n standard output differs"
    same OUT/PCO/R$n.TXT OUT/PAO/R$n.TXT "case $n exit status differs (PAO)"
done < cases.txt

# state DIR IMAGE: every file left behind, with its size and, for
# files under 16 MB, its checksum
state() {
    rm -rf flop
    mkdir flop
    mcopy -s -n -i "$2" '::*' flop/ 2>/dev/null
    for top in "$1" flop; do
        (cd "$top" && find . | sort | while IFS= read -r f; do
            if [ -d "$f" ]; then
                echo "$top $f/"
            else
                s=$(wc -c < "$f" | tr -d ' ')
                c=-
                [ "$s" -lt 16777216 ] && c=$(cksum < "$f")
                echo "$top $f $s $c"
            fi
        done) | sed "s|^$1 |dir |"
    done
}

state PC PC.IMG > state.c
for p in PA PA2; do
    state $p $p.IMG > state.t
    args="files left behind, $p"
    same state.c state.t "files left behind differ in $p (< PC, > $p)"
done
state PCO PCO.IMG > state.c
state PAO PAO.IMG > state.t
args="files left behind, PAO"
same state.c state.t "files left behind differ in PAO (< PCO, > PAO)"

# exact CASE FILE: FILE from PC and PA must be the printf(1) format on
# stdin
exact() {
    # shellcheck disable=SC2059
    printf "$(cat)" > want.txt
    for p in PC PA; do
        if cmp -s want.txt "OUT/$p/O$1.TXT"; then
            ok
        else
            not_ok "OUT/$p/O$1.TXT is not as expected"
            od -c "OUT/$p/O$1.TXT" 2>&1 | sed 's/^/    /'
        fi
    done
}

num() { grep -n -x -F -e "$1" cases.txt | head -1 | cut -d: -f1; }

exact "$(num '--version')" <<EOS
truncate (dos-truncate16) $(cat "$here/../../VERSION")\r\n
EOS
exact "$(num '--bogus -s 5 x.dat')" <<'EOS'
truncate: unrecognized option '--bogus'\r\nTry 'truncate --help' for more information.\r\n
EOS
exact "$(num '-s 1M a:\full.dat')" <<'EOS'
truncate: failed to truncate 'a:\\full.dat' at 1048576 bytes: No space left on device\r\n
EOS
exact "$(num '-s 5 big3g.dat')" <<'EOS'
truncate: cannot get the size of 'big3g.dat': No error\r\n
EOS
exact "$(num '-s 5 n40.dat big3g.dat')" <<'EOS'
truncate: cannot get the size of 'big3g.dat': No error\r\n
EOS
exact "$(num '-s 5 ro.dat')" <<'EOS'
truncate: cannot open 'ro.dat' for writing: Permission denied\r\n
EOS
exact "$(num '-s 1P n14.dat')" <<'EOS'
truncate: Invalid number: '1P': Value too large\r\n
EOS

# ------------------------------------------------------------------

echo "$pass passed, $fail failed"
if [ "$fail" -ne 0 ] || [ "${KEEP:-0}" = 1 ]; then
    echo "work directory: $work"
else
    rm -rf "$work"
fi
[ "$fail" -eq 0 ]
