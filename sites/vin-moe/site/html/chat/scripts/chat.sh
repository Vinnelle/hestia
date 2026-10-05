#!/bin/sh
#
# chat runner for Linux, served at https://chat.vin.moe
#
# Run it with:
#
#   curl -fsSL https://chat.vin.moe | sh
#
# This script downloads the latest release of chat from GitHub, checks that
# it was signed with chat's release key, runs it, and deletes it again when
# chat exits. It installs nothing, never asks for root, and changes no
# settings. The only files it leaves behind are ones chat itself writes, and
# chat writes nothing unless you ask it to (:install).
#
# It takes five steps:
#
#   1. Pick the release file that fits this computer.
#   2. Download it, with SHA256SUMS and SHA256SUMS.minisig, from the latest
#      release on https://github.com/Vinnelle/chat/releases into a new
#      temporary folder that only you can read.
#   3. Check that SHA256SUMS is signed with chat's release key, the public
#      key in minisign_pub below (the same key as minisign.pub in the chat
#      repository). Releases are signed offline, never on GitHub, so even
#      someone who took over the GitHub account couldn't pass this check.
#   4. Check the downloaded program against its SHA-256 in SHA256SUMS.
#   5. Run chat, and delete the temporary folder when it exits.
#
# If any step fails, the script stops before running anything it downloaded.
#
# It runs in any POSIX shell (sh, bash, zsh, dash and so on). The command
# above pipes it into sh, so it works whichever shell you type it in, fish
# included. It also works from Git Bash on Windows, though on Windows the
# PowerShell version is simpler:
#
#   irm https://chat.vin.moe | iex
#
# To read the script before you run it, open
# https://chat.vin.moe/chat.sh in a browser. To check that's the file
# your shell would get, compare the SHA-256 printed by
#
#   curl -fsSL https://chat.vin.moe | sha256sum
#
# with the one shown on https://chat.vin.moe.

# Stop at the first command that fails, and treat unset variables as errors.
set -eu

# Where releases come from, and the public half of chat's release key. Only
# the public half is here: it can check signatures, but it can't make them.
repo=https://github.com/Vinnelle/chat
minisign_pub=RWSR+ZdG2DibcI2waaAukeezQJcX5D5BcYHmZ2lOzLVATd2FnlS7YEZB

# Print a status line. It goes to stderr, so it never mixes with chat's output.
say() {
    printf 'chat: %s\n' "$*" >&2
}

# Print why the script is stopping, and stop. The trap set in main deletes
# the temporary folder on the way out.
die() {
    say "$*"
    exit 1
}

# Stop early, with a clear message, if a tool this script needs is missing.
need() {
    command -v "$1" >/dev/null 2>&1 || die "this needs $1, which isn't installed"
}

# Download over HTTPS only. --proto '=https' refuses any redirect to plain
# HTTP, --tlsv1.2 refuses older TLS, and -f fails on an HTTP error instead of
# saving the error page as if it were the file.
get() {
    curl --proto '=https' --tlsv1.2 -fsSL "$@"
}

# Check SHA256SUMS against SHA256SUMS.minisig with chat's release key. If
# minisign is installed, it does the check. Otherwise OpenSSL 3 does the same
# check by hand: minisign signs the BLAKE2b-512 hash of a file with Ed25519,
# so the steps below take the 64-byte signature out of the .minisig file, put
# the 32-byte public key in the DER form OpenSSL reads, hash SHA256SUMS with
# BLAKE2b-512, and ask OpenSSL whether the signature matches that hash.
check_signature() {
    if command -v minisign >/dev/null 2>&1; then
        minisign -Vqm "$dir/SHA256SUMS" -P "$minisign_pub"
        return
    fi
    # The second line of a .minisig file is the signature in base64: two bytes
    # naming the algorithm ("ED" means a signed BLAKE2b-512 hash), eight bytes
    # of key id, then the 64-byte Ed25519 signature.
    sed -n 2p "$dir/SHA256SUMS.minisig" | base64 -d >"$dir/sig"
    [ "$(head -c 2 "$dir/sig")" = ED ] || return 1
    tail -c 64 "$dir/sig" >"$dir/sig.ed25519"
    # The public key decodes the same way: "Ed", eight bytes of key id, then
    # the 32-byte key. The first printf writes the fixed 12-byte header that
    # turns those 32 bytes into an Ed25519 public key file OpenSSL can read.
    {
        printf '\060\052\060\005\006\003\053\145\160\003\041\000'
        printf '%s' "$minisign_pub" | base64 -d | tail -c 32
    } >"$dir/pub.der"
    openssl dgst -blake2b512 -binary "$dir/SHA256SUMS" >"$dir/SHA256SUMS.blake2b"
    openssl pkeyutl -verify -pubin -keyform DER -inkey "$dir/pub.der" -rawin \
        -in "$dir/SHA256SUMS.blake2b" -sigfile "$dir/sig.ed25519" >/dev/null
}

main() {
    # Step 1: pick the release file. Git Bash, MSYS2 and Cygwin run on
    # Windows, so they get the Windows build, which runs in the same terminal.
    case "$(uname -s)" in
        Linux) asset=chat-linux-x86_64 bin=chat ;;
        MINGW* | MSYS* | CYGWIN*) asset=chat-windows-x86_64.exe bin=chat.exe ;;
        *) die "release builds are for Linux and Windows. To build chat yourself, see $repo" ;;
    esac
    # Release builds are for 64-bit x86 only.
    case "$(uname -m)" in
        x86_64 | amd64) ;;
        *) die "release builds are for x86_64 only. To build chat yourself, see $repo" ;;
    esac
    # Check for every tool this needs before downloading anything.
    need curl
    need sha256sum
    command -v minisign >/dev/null 2>&1 || openssl pkeyutl -help 2>&1 | grep -q rawin ||
        die "checking the release signature needs minisign, or OpenSSL 3 or newer"
    # chat draws a full-screen interface, so it needs a terminal. Under
    # "curl | sh", this script's input is the download rather than your
    # keyboard, so chat reads from the terminal itself, /dev/tty.
    (exec </dev/tty) 2>/dev/null || die "chat needs a terminal to run in"

    # Step 2: a new folder only you can read (mktemp -d makes it with mode
    # 700). $XDG_RUNTIME_DIR is used when it exists: it belongs to you alone
    # and is kept in memory, so on most Linux desktops the download never
    # touches the disk.
    tmp=${TMPDIR:-/tmp}
    if [ -d "${XDG_RUNTIME_DIR:-}" ] && [ -w "$XDG_RUNTIME_DIR" ]; then
        tmp=$XDG_RUNTIME_DIR
    fi
    dir=$(mktemp -d "$tmp/chat.XXXXXX")
    # Delete the folder however the script ends: when chat exits, on an
    # error, on Ctrl+C, when it's killed, or when the terminal closes.
    trap 'rm -rf "$dir"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    trap 'exit 129' HUP

    # Find the latest release. GitHub redirects /releases/latest to
    # /releases/tag/<version>, and the version is the last part of that
    # address. Anything that doesn't look like a version tag is refused.
    tag=$(get -I -o /dev/null -w '%{url_effective}' "$repo/releases/latest")
    tag=${tag##*/}
    case "$tag" in
        v[0-9]*) ;;
        *) die "couldn't find the latest release at $repo/releases" ;;
    esac

    say "downloading $tag"
    for file in "$asset" SHA256SUMS SHA256SUMS.minisig; do
        get -o "$dir/$file" "$repo/releases/download/$tag/$file"
    done

    # Step 3: the signature. Nothing downloaded has been run yet, so stopping
    # here is safe.
    check_signature || die "the release signature didn't verify"
    # Step 4: find the program's line in SHA256SUMS, which is now known to be
    # genuine, and compare the hashes.
    sum=$(awk -v asset="$asset" '$2 == asset { print $1 }' "$dir/SHA256SUMS")
    [ -n "$sum" ] || die "SHA256SUMS has no line for $asset"
    [ "$(sha256sum "$dir/$asset" | cut -d ' ' -f 1)" = "$sum" ] ||
        die "$asset doesn't match SHA256SUMS"

    # Step 5: name it chat, let only you run it, and start it with any options
    # given after "sh -s --". When chat exits, the trap above deletes the
    # folder, and the program with it.
    mv "$dir/$asset" "$dir/$bin"
    chmod 700 "$dir/$bin"
    say "signature and checksum match. Starting chat, which is deleted again when it exits"
    "$dir/$bin" "$@" </dev/tty
}

# Everything above only defines functions, so a download cut off partway
# runs nothing. This line starts the runner once the whole script has
# arrived.
main "$@"
