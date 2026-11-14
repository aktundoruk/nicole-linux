#!/usr/bin/env bash
# Prepare the project's kernel patches for upstream review (inside the Linux VM). Sends nothing.
#
#  1. a clean worktree of the VM kernel repo at the base tag (never the build tree)
#  2. each patch of the series as one commit: git am, or, for the hand-written ones,
#     git apply --recount plus a commit from the patch's own From/Date/Subject/message
#  3. git format-patch per series into out/upstream/<series>/, then checkpatch --strict
#     (each file's report next to it) and get_maintainer.pl (who it would go to)
#
# No Signed-off-by is added: the DCO line is the author's own statement and is added by
# him (git commit -s / format-patch -s) when he decides to send.
# AI involvement: linux-next dropped the Assisted-by tag (coding-assistants.rst) and asks for
# transparency in the changelog (generated-content.rst), so each commit's Assisted-by line
# is replaced by a paragraph saying what the assistant did and how it was tested (Doruk's
# decision, 10 Kasım 2026). TEST_NOTU overrides the test sentence.
#
# Usage: yukari-hazirla.sh [--taban TAG] SERIES PATCH...
#   SERIES  a name (directory under out/upstream/), PATCH paths relative to the project
set -euo pipefail

PROJECT=$(cd "$(dirname "$0")/../.." && pwd)
REPO=/mnt/lima-razer-build/src/linux-v7.3-rc6
TABAN=v7.3-rc6
[ "${1:-}" = --taban ] && { TABAN=$2; shift 2; }
SERI=${1:?series name}; shift
[ $# -gt 0 ] || { echo "no patches" >&2; exit 2; }
AGAC=/mnt/lima-razer-build/yukari/$SERI
CIKTI=$PROJECT/out/upstream/$SERI

git -C "$REPO" worktree remove --force "$AGAC" 2>/dev/null || true
git -C "$REPO" worktree prune
mkdir -p "$(dirname "$AGAC")"
git -C "$REPO" worktree add -q --detach "$AGAC" "$TABAN"
cd "$AGAC"
git config user.name "Doruk Aktun"
git config user.email "info@dorukaktun.com"

# every commit says how an AI assistant was involved, as a changelog paragraph
TEST_NOTU=${TEST_NOTU:-"Tested on the Razer Edge (SM8350) with v7.3-rc6 and board patches; build-tested with W=1 on ${TABAN_ADI:-$TABAN}."}
izli() {
	git log -1 --format=%B | python3 -c '
import re, sys
mesaj, test = sys.stdin.read().rstrip(), sys.argv[1]
paragraf = ("The problem was found and the fix and this message drafted with an AI coding "
            "assistant (Claude Opus 5.5) during the Razer Edge bring-up; I reviewed and tested "
            "it and take responsibility for it. " + test)
import textwrap
paragraf = textwrap.fill(paragraf, 72)
satirlar = [s for s in mesaj.splitlines() if not s.startswith("Assisted-by:")]
# the trailer block: the last run of "Key: value" lines
i = len(satirlar)
while i > 0 and re.match(r"[A-Za-z-]+: ", satirlar[i - 1]):
    i -= 1
govde, iz = "\n".join(satirlar[:i]).rstrip(), "\n".join(satirlar[i:])
print(govde + "\n\n" + paragraf + ("\n\n" + iz if iz else ""))
' "$TEST_NOTU" > /tmp/yukari-iz
	git commit -q --amend --cleanup=verbatim -F /tmp/yukari-iz
}

for p in "$@"; do
	yol=$PROJECT/$p
	if git am -q --keep-cr "$yol" 2>/dev/null; then
		echo "am     $p"
		izli
		continue
	fi
	git am --abort 2>/dev/null || true
	git apply --recount --whitespace=nowarn "$yol" || { echo "UYGULANAMADI $p" >&2; exit 1; }
	python3 - "$yol" > /tmp/yukari-mesaj <<'PY'
import email.utils, re, sys
metin = open(sys.argv[1], encoding="utf-8").read()
bas, _, govde = metin.partition("\n\n")
basliklar = {}
for satir in bas.splitlines():
    m = re.match(r"(From|Date|Subject): (.*)", satir)
    if m:
        basliklar[m.group(1)] = m.group(2)
konu = re.sub(r"^\[PATCH[^\]]*\]\s*", "", basliklar.get("Subject", "?"))
mesaj = re.split(r"\n---\n|\ndiff --git ", govde, maxsplit=1)[0].rstrip()
print(konu + "\n\n" + mesaj)
PY
	git add -A
	tarih=$(sed -n 's/^Date: //p' "$yol" | head -1)
	git -c core.commentChar=';' commit -q --cleanup=verbatim -F /tmp/yukari-mesaj \
		--author="Doruk Aktun <info@dorukaktun.com>" ${tarih:+--date="$tarih"}
	echo "apply  $p"
	izli
done

rm -rf "$CIKTI"; mkdir -p "$CIKTI"
n=$(git rev-list --count "$TABAN"..HEAD)
kapak=; [ "$n" -gt 1 ] && kapak=--cover-letter
git format-patch -q $kapak --base="$TABAN" -o "$CIKTI" "$TABAN"..HEAD
for f in "$CIKTI"/*.patch; do
	case "$f" in *0000-cover-letter.patch) continue ;; esac
	perl scripts/checkpatch.pl --strict --terse "$f" > "$f.checkpatch" 2>&1 || true
done
perl scripts/get_maintainer.pl --no-rolestats --nogit-fallback "$CIKTI"/0*.patch \
	| grep -v cover-letter > "$CIKTI/alicilar.txt" 2>/dev/null || true
echo "== $SERI: $n yama -> $CIKTI"
for f in "$CIKTI"/*.checkpatch; do
	printf '%-70s %s\n' "$(basename "${f%.checkpatch}" | cut -c1-68)" "$(tail -1 "$f")"
done
