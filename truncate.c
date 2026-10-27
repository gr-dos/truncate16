/*
 * truncate - shrink or extend the size of a file to the specified size
 *
 * A GNU coreutils compatible truncate for 16-bit MS-DOS (Open Watcom C
 * with libc16).
 */

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <limits.h>
#include <fcntl.h>
#include <io.h>
#include <sys/stat.h>
#include <libc16.h>

#ifndef VERSION
#define VERSION   "unknown"
#endif

/* how SIZE applies to the current size of a file */
#define MOD_SET      0      /* N   set to */
#define MOD_EXTEND   '+'    /* +N  extend by */
#define MOD_REDUCE   '-'    /* -N  reduce by */
#define MOD_ATMOST   '<'    /* <N  at most */
#define MOD_ATLEAST  '>'    /* >N  at least */
#define MOD_ROUNDDN  '/'    /* /N  round down to a multiple of */
#define MOD_ROUNDUP  '%'    /* %N  round up to a multiple of */

static int opt_no_create = 0;
static int size_mod = MOD_SET;
static long size_val = 0;

static const char *progname = "truncate";

/* Writes the strings, up to a null pointer, to fp. */
static void put(FILE *fp, const char *s, ...)
{
    va_list ap;

    va_start(ap, s);
    for (; s != NULL; s = va_arg(ap, const char *))
        fputs(s, fp);
    va_end(ap);
}

static void usage(FILE *fp)
{
    fputs(
        "Usage: truncate OPTION... FILE...\n"
        "Shrink or extend the size of each FILE to the specified size.\n"
        "\n"
        "A FILE argument that does not exist is created.\n"
        "\n"
        "If a FILE is larger than the specified size, the extra data is lost.\n"
        "If a FILE is shorter, it is extended and the extended part reads\n"
        "as zero bytes.\n"
        "\n"
        "  -c, --no-create        do not create any files\n"
        "  -s, --size=SIZE        set or adjust the file size by SIZE bytes\n"
        "  -h, --help             display this help and exit\n"
        "      --version          output version information and exit\n"
        "\n"
        "SIZE is an integer and optional unit (example: 10K is 10*1024).\n"
        "Units are K,M,G (powers of 1024) or KB,MB,GB (powers of 1000).\n"
        "Binary prefixes can be used, too: KiB=K, MiB=M, and so on.\n"
        "\n"
        "SIZE may also be prefixed by one of the following modifying characters:\n"
        "'+' extend by, '-' reduce by, '<' at most, '>' at least,\n"
        "'/' round down to multiple of, '%' round up to multiple of.\n", fp);
}

static void try_help(void)
{
    fputs("Try 'truncate --help' for more information.\n", stderr);
}

/* Parse SIZE into size_mod and size_val.  Returns 0 on success, or
   prints a diagnostic and returns -1. */
static int parse_size(const char *s)
{
    const char *p = s;
    unsigned long n = 0, mult = 1, base = 1024;
    int power = 0;

    while (*p == ' ' || *p == '\t')
        p++;
    if (*p != '\0' && strchr("+-<>/%", *p) != NULL)
        size_mod = *p++;
    else
        size_mod = MOD_SET;
    while (*p == ' ' || *p == '\t')
        p++;

    if (*p < '0' || *p > '9')
        goto invalid;
    for (; *p >= '0' && *p <= '9'; p++) {
        if (n > (LONG_MAX - (*p - '0')) / 10)
            goto toolarge;
        n = n * 10 + (*p - '0');
    }

    if (*p != '\0') {
        switch (*p) {
        case 'k': case 'K': power = 1; break;
        case 'm': case 'M': power = 2; break;
        case 'g': case 'G': power = 3; break;
        case 't': case 'T': power = 4; break;
        case 'P': power = 5; break;
        case 'E': power = 6; break;
        case 'Z': power = 7; break;
        case 'Y': power = 8; break;
        case 'R': power = 9; break;
        case 'Q': power = 10; break;
        default: goto invalid;
        }
        p++;
        if (p[0] == 'B' && p[1] == '\0')
            base = 1000;
        else if (p[0] == 'i' && p[1] == 'B' && p[2] == '\0')
            ;
        else if (p[0] != '\0')
            goto invalid;
        /* zero times any unit is zero, even one too large for a long */
        while (n != 0 && power-- > 0) {
            if (mult > LONG_MAX / base)
                goto toolarge;
            mult *= base;
        }
        if (n > LONG_MAX / mult)
            goto toolarge;
        n *= mult;
    }

    if (n == 0 && (size_mod == MOD_ROUNDDN || size_mod == MOD_ROUNDUP)) {
        put(stderr, progname, ": division by zero\n", NULL);
        return -1;
    }
    size_val = (long)n;
    return 0;

invalid:
    put(stderr, progname, ": Invalid number: '", s, "'\n", NULL);
    return -1;
toolarge:
    put(stderr, progname, ": Invalid number: '", s, "': Value too large\n",
        NULL);
    return -1;
}

/* The new size of a file now fsize bytes long, or -1 on overflow. */
static long new_size(long fsize)
{
    long r;

    switch (size_mod) {
    case MOD_EXTEND:
        return fsize > LONG_MAX - size_val ? -1 : fsize + size_val;
    case MOD_REDUCE:
        return fsize > size_val ? fsize - size_val : 0;
    case MOD_ATMOST:
        return fsize < size_val ? fsize : size_val;
    case MOD_ATLEAST:
        return fsize > size_val ? fsize : size_val;
    case MOD_ROUNDDN:
        return fsize / size_val * size_val;
    case MOD_ROUNDUP:
        r = fsize % size_val;
        if (r == 0)
            return fsize;
        return fsize - r > LONG_MAX - size_val ? -1 : fsize - r + size_val;
    }
    return size_val;
}

static int truncate_one(const char *name)
{
    int fd, flags = O_RDWR | O_BINARY;
    long fsize, nsize;
    char nbuf[12];

    if (!opt_no_create)
        flags |= O_CREAT;
    fd = open(name, flags, S_IREAD | S_IWRITE);
    if (fd < 0) {
        if (opt_no_create && errno == ENOENT)
            return 0;
        put(stderr, progname, ": cannot open '", name, "' for writing: ",
            strerror(errno), "\n", NULL);
        return 1;
    }

    fsize = filelength(fd);
    if (fsize < 0) {
        put(stderr, progname, ": cannot get the size of '", name, "': ",
            strerror(errno), "\n", NULL);
        close(fd);
        return 1;
    }
    nsize = new_size(fsize);
    if (nsize < 0) {
        put(stderr, progname, ": overflow extending size of file '", name,
            "'\n", NULL);
        close(fd);
        return 1;
    }
    if (nsize != fsize && chsize(fd, nsize) != 0) {
        put(stderr, progname, ": failed to truncate '", name, "' at ",
            libc16_ltoa(nsize, nbuf, 10), " bytes: ", strerror(errno), "\n",
            NULL);
        close(fd);
        return 1;
    }
    if (close(fd) != 0) {
        put(stderr, progname, ": failed to close '", name, "': ",
            strerror(errno), "\n", NULL);
        return 1;
    }
    return 0;
}

int main(int argc, char **argv)
{
    int i, nfiles = 0, endopts = 0, have_size = 0;
    int rc = 0;
    const char *arg;
    char opt[2] = { 0, 0 };

    for (i = 1; i < argc; i++) {
        const char *a = argv[i];

        if (endopts || a[0] != '-' || a[1] == '\0') {
            nfiles++;
            continue;
        }
        argv[i] = NULL;
        if (a[1] == '-') {
            if (a[2] == '\0')                       endopts = 1;
            else if (strcmp(a, "--no-create") == 0) opt_no_create = 1;
            else if (strncmp(a, "--size", 6) == 0 &&
                     (a[6] == '\0' || a[6] == '=')) {
                if (a[6] == '=') {
                    arg = a + 7;
                } else if (i + 1 < argc) {
                    arg = argv[++i];
                    argv[i] = NULL;
                } else {
                    put(stderr, progname, ": option '--size' requires an "
                        "argument\n", NULL);
                    try_help();
                    return 1;
                }
                if (parse_size(arg) != 0)
                    return 1;
                have_size = 1;
            } else if (strcmp(a, "--help") == 0) {
                usage(stdout);
                return 0;
            } else if (strcmp(a, "--version") == 0) {
                fputs("truncate (dos-truncate16) " VERSION "\n", stdout);
                return 0;
            } else {
                put(stderr, progname, ": unrecognized option '", a, "'\n",
                    NULL);
                try_help();
                return 1;
            }
            continue;
        }
        for (a++; *a; a++) {
            switch (*a) {
            case 'c': opt_no_create = 1; break;
            case 's':
                if (a[1] != '\0') {
                    arg = a + 1;
                } else if (i + 1 < argc) {
                    arg = argv[++i];
                    argv[i] = NULL;
                } else {
                    put(stderr, progname, ": option requires an argument "
                        "-- 's'\n", NULL);
                    try_help();
                    return 1;
                }
                if (parse_size(arg) != 0)
                    return 1;
                have_size = 1;
                a = "s";                /* rest of the word was SIZE */
                break;
            case 'h':
            case '?':
                usage(stdout);
                return 0;
            default:
                opt[0] = *a;
                put(stderr, progname, ": invalid option -- '", opt, "'\n",
                    NULL);
                try_help();
                return 1;
            }
        }
    }

    if (!have_size) {
        put(stderr, progname, ": you must specify '--size'\n", NULL);
        try_help();
        return 1;
    }
    if (nfiles == 0) {
        put(stderr, progname, ": missing file operand\n", NULL);
        try_help();
        return 1;
    }

    for (i = 1; i < argc; i++)
        if (argv[i] != NULL)
            rc |= truncate_one(argv[i]);
    return rc;
}
