#!/bin/sh
set -eu

page=chat/index.html

variant() {
  [ "$(grep -c "$2" "chat/scripts/$1")" = 1 ] || {
    echo "embed-runner.sh: chat/scripts/$1 needs exactly one line matching $2" >&2
    exit 1
  }
  sed "/$2/s/$3/$4/" "chat/scripts/$1" >"chat/scripts/${1%.*}-$5.${1##*.}"
}

variant chat.sh '^channel=stable$' stable beta beta
variant chat.ps1 "^ *\\\$channel = 'stable'\$" stable beta beta
for script in chat.sh chat-beta.sh; do
  variant "$script" '^session=$' '$' vin-moe-party party
done
for script in chat.ps1 chat-beta.ps1; do
  variant "$script" "^ *\\\$session = ''\$" "''" "'vin-moe-party'" party
done

for script in chat/scripts/*; do
  name="${script##*/}"
  code="@@script:$name@@"
  hash="@@sha256:$name@@"
  for marker in "$code" "$hash"; do
    grep -qF "$marker" "$page" || {
      echo "embed-runner.sh: $page has no $marker" >&2
      exit 1
    }
  done

  sum="$(sha256sum "$script" | cut -d ' ' -f 1)"
  escaped="$(mktemp)"
  sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' "$script" >"$escaped"

  awk -v sum="$sum" -v body="$escaped" -v code="$code" -v hash="$hash" '
    {
      while ((i = index($0, hash)) > 0) $0 = substr($0, 1, i - 1) sum substr($0, i + length(hash))
      i = index($0, code)
      if (!i) { print; next }
      printf "%s", substr($0, 1, i - 1)
      sep = ""
      while ((getline line < body) > 0) { printf "%s%s", sep, line; sep = "\n" }
      print substr($0, i + length(code))
    }
  ' "$page" >"$page.tmp"

  mv "$page.tmp" "$page"
  rm -f "$escaped"
done

if grep -q '@@script:\|@@sha256:' "$page"; then
  echo "embed-runner.sh: $page names a script that isn't in chat/scripts" >&2
  exit 1
fi
