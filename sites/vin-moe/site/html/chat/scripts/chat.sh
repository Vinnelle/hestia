#!/bin/sh
set -eu

repo=https://github.com/Vinnelle/chat
minisign_pub=RWSR+ZdG2DibcI2waaAukeezQJcX5D5BcYHmZ2lOzLVATd2FnlS7YEZB

say() {
    printf 'chat: %s\n' "$*" >&2
}

die() {
    say "$*"
    exit 1
}

need() {
    command -v "$1" >/dev/null 2>&1 || die "this needs $1, which isn't installed"
}

get() {
    curl --proto '=https' --tlsv1.2 -fsSL "$@"
}

check_signature() {
    if command -v minisign >/dev/null 2>&1; then
        minisign -Vqm "$dir/SHA256SUMS" -P "$minisign_pub"
        return
    fi
    sed -n 2p "$dir/SHA256SUMS.minisig" | base64 -d >"$dir/sig"
    [ "$(head -c 2 "$dir/sig")" = ED ] || return 1
    tail -c 64 "$dir/sig" >"$dir/sig.ed25519"
    {
        printf '\060\052\060\005\006\003\053\145\160\003\041\000'
        printf '%s' "$minisign_pub" | base64 -d | tail -c 32
    } >"$dir/pub.der"
    openssl dgst -blake2b512 -binary "$dir/SHA256SUMS" >"$dir/SHA256SUMS.blake2b"
    openssl pkeyutl -verify -pubin -keyform DER -inkey "$dir/pub.der" -rawin \
        -in "$dir/SHA256SUMS.blake2b" -sigfile "$dir/sig.ed25519" >/dev/null
}

main() {
    case "$(uname -s)" in
        Linux) asset=chat-linux-x86_64 bin=chat ;;
        MINGW* | MSYS* | CYGWIN*) asset=chat-windows-x86_64.exe bin=chat.exe ;;
        *) die "release builds are for Linux and Windows. To build chat yourself, see $repo" ;;
    esac
    case "$(uname -m)" in
        x86_64 | amd64) ;;
        *) die "release builds are for x86_64 only. To build chat yourself, see $repo" ;;
    esac
    need curl
    need sha256sum
    command -v minisign >/dev/null 2>&1 || openssl pkeyutl -help 2>&1 | grep -q rawin ||
        die "checking the release signature needs minisign, or OpenSSL 3 or newer"
    (exec </dev/tty) 2>/dev/null || die "chat needs a terminal to run in"

    tmp=${TMPDIR:-/tmp}
    if [ -d "${XDG_RUNTIME_DIR:-}" ] && [ -w "$XDG_RUNTIME_DIR" ]; then
        tmp=$XDG_RUNTIME_DIR
    fi
    dir=$(mktemp -d "$tmp/chat.XXXXXX")
    trap 'rm -rf "$dir"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    trap 'exit 129' HUP

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

    check_signature || die "the release signature didn't verify"
    sum=$(awk -v asset="$asset" '$2 == asset { print $1 }' "$dir/SHA256SUMS")
    [ -n "$sum" ] || die "SHA256SUMS has no line for $asset"
    [ "$(sha256sum "$dir/$asset" | cut -d ' ' -f 1)" = "$sum" ] ||
        die "$asset doesn't match SHA256SUMS"

    mv "$dir/$asset" "$dir/$bin"
    chmod 700 "$dir/$bin"
    say "signature and checksum match. Starting chat, which is deleted again when it exits"
    "$dir/$bin" "$@" </dev/tty
}

main "$@"
