# truncate16

A GNU coreutils compatible `truncate` for 16-bit MS-DOS, built with
Open Watcom.

The resulting `truncate.exe` is a small-model, real-mode 8086
executable that runs on any DOS from an original PC up. It follows the
conventions of [hello16](https://github.com/gr-dos/hello16).

`asm/` holds an experimental 8086 assembly version, `truncate.com`,
which behaves the same and is 80% smaller (3,314 bytes against 16,184).
`truncate.c` stays the reference and the default build. See
[asm/README.md](asm/README.md).

## Usage

    truncate OPTION... FILE...

Shrink or extend the size of each FILE to the specified size. A FILE
that does not exist is created (unless `-c` is given). If a FILE is
larger than the specified size, the extra data is lost; if it is
shorter, it is extended with zero bytes.

    -c, --no-create     do not create any files
    -s, --size=SIZE     set or adjust the file size by SIZE bytes
    -h, --help          show help (also -?)
        --version       show version

`--size` is required. The size may be given as `-s SIZE`, `-sSIZE`,
`--size SIZE` or `--size=SIZE`. Options may appear anywhere on the
command line; `--` ends them.

SIZE is an integer with an optional unit: `K`, `M`, `G`, ... are powers
of 1024 (`KiB`, `MiB`, ... are the same) and `KB`, `MB`, `GB`, ... are
powers of 1000. It may be prefixed by one of

    +   extend by          -   reduce by (not below 0)
    <   at most            >   at least
    /   round down to a multiple of
    %   round up to a multiple of

Examples:

    truncate -s 0 LOG.TXT          empty a file
    truncate -s 1M DISK.IMG        create (or resize) a 1 MiB file
    truncate -c -s +512 DATA.BIN   grow an existing file by 512 bytes
    truncate -s "<64K" BIG.LOG     cap a file at 64 KiB
    truncate -s %512 IMAGE.BIN     pad to a multiple of 512 bytes

DOS notes:

- `<` and `>` are redirection characters, so quote them: `-s "<50"`.
- In a batch file, `%` must be doubled: `-s %%512`.
- Sizes are limited to 2147483647 bytes (2 GiB - 1), the most a DOS
  file offset can hold; larger sizes are an error.
- Extending a file writes real zero bytes (DOS has no sparse files),
  so growing a file by a large amount takes time and disk space.

The exit code is 0 on success and 1 on any error (bad option or size,
missing operand, or a file that could not be opened or resized). With
`-c`, a missing file is silently skipped and is not an error.

## Conventions

### 1. Build and test on Linux with GNU make and Open Watcom

Everything is built and tested on a Linux host, cross-compiling with the
Linux-hosted Open Watcom toolchain driven by GNU make:

    make         # builds truncate.exe
    make test    # runs the test suite under DOSBox-X
    make clean

### 2. Watcom location

The `Makefile` uses the Open Watcom installation in `~/opt/watcom` by
default. Point it somewhere else on the command line:

    make WATCOM=/path/to/watcom
    make test WATCOM=/path/to/watcom

The `Makefile` sets `INCLUDE` and puts `$(WATCOM)/binl64` and
`$(WATCOM)/binl` on `PATH` itself, so there is no environment to source
first. In CI, `open-watcom/setup-watcom` sets `WATCOM`, which overrides
the default.

### 3. `main` is protected

`main` only changes by merging a pull request. Branch protection on
`main`:

- requires a pull request before merging (no direct pushes),
- requires the `test` status check from `ci.yml` to pass,
- applies to administrators too ("Do not allow bypassing the above
  settings" / `enforce_admins`),
- disallows force pushes and deletion.

Work happens on a feature branch (for example `graham/impl`) and lands
through a PR. To set the same protection on a new repository:

    gh api -X PUT repos/OWNER/REPO/branches/main/protection --input - <<'EOF'
    {"required_status_checks":{"strict":false,"checks":[{"context":"test","app_id":15368}]},
     "enforce_admins":true,
     "required_pull_request_reviews":{"required_approving_review_count":0},
     "restrictions":null,"allow_force_pushes":false,"allow_deletions":false}
    EOF

(`app_id` 15368 is GitHub Actions, so only Actions can satisfy the check.)

### 4. Tests run under DOSBox-X via `make test`

`make test` runs `tests/run.sh`, which needs `dosbox-x` on the host
(override with `DOSBOX=`; set `KEEP=1` to keep the work directory).

The script builds fixtures in a temporary directory, writes one batch
file (`steps.bat`) holding every DOS-side step, runs it in a headless
DOSBox-X, then checks the results on the host. Step N records the
program's exit status in `RN.TXT` (via `rc.bat`) and its standard output
in `ON.TXT`. DOS cannot redirect standard error, so diagnostics are not
checked. To add a test, add a step to `steps.bat` and the matching
`rc` / `expect` / `check` lines.

### 5. CI must pass before merging

`.github/workflows/ci.yml` builds and runs `make test` on every pull
request and every push to `main`. It also runs `make -C asm test`, which
builds `asm/truncate.com` and tests it against `truncate.exe`. Its `test` job is a required status
check, so a PR cannot be merged until it passes.

### 6. `--version` and the `VERSION` file

`truncate --version` prints

    truncate (dos-truncate16) 0.01

The version is the one line in `VERSION`; the `Makefile` compiles it in
as `-DVERSION="..."`. Versions are MS-DOS style, not semantic versioning:
they start at `0.01` and go `0.02`, `0.03`, ... `1.00`, `1.01`, and so on.
`make test` checks that `--version` matches `VERSION`.

### 7. Releases

`.github/workflows/release.yml` runs on every push to `main`, which (by
rule 3) is always a PR merge. If `VERSION` names a version that has no
`v<VERSION>` tag yet, it builds and tests `truncate.exe`, tags the merge
commit `v<VERSION>`, and publishes a GitHub release with `truncate.exe`
attached. If the version is unchanged, it does nothing. To release, bump
`VERSION` in the PR.

## Files

- `truncate.c`: the program
- `Makefile`: Open Watcom build (`make`, `make test`, `make clean`)
- `VERSION`: the version, compiled in and printed by `--version`
- `tests/run.sh`: the test suite, run under DOSBox-X by `make test`
- `.github/workflows/ci.yml`: build and test on PRs and pushes to `main`
- `.github/workflows/release.yml`: tag and release when `VERSION` changes
- `asm/`: the optional 8086 assembly version (`make -C asm`,
  `make -C asm test`, `make -C asm measure`); see `asm/README.md`

## License

MIT. See `LICENSE`.
