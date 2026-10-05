#!/bin/sh
set -eu

page=chat/index.html
script=chat/scripts/chat.sh

for marker in @@runner-script@@ @@runner-sha256@@; do
  grep -q "$marker" "$page" || {
    echo "embed-runner.sh: $page has no $marker" >&2
    exit 1
  }
done

sum="$(sha256sum "$script" | cut -d ' ' -f 1)"
escaped="$(mktemp)"
sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' "$script" >"$escaped"

awk -v sum="$sum" -v body="$escaped" '
  {
    gsub(/@@runner-sha256@@/, sum)
    i = index($0, "@@runner-script@@")
    if (!i) { print; next }
    printf "%s", substr($0, 1, i - 1)
    sep = ""
    while ((getline line < body) > 0) { printf "%s%s", sep, line; sep = "\n" }
    print substr($0, i + length("@@runner-script@@"))
  }
' "$page" >"$page.tmp"

mv "$page.tmp" "$page"
rm -f "$escaped"
