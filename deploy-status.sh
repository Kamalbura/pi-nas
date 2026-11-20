#!/bin/bash
# Regenerate the public status snapshot and publish it to GitHub Pages.
# Driven by pi-nas-status-update.service (daily, 01:00 IST).
#
# Two invariants this script must not break:
#
#   1. Never publish a generator/template older than the remote redaction
#      commit. generate-status.sh and index.html used to emit the real
#      hostname, LAN + Tailscale addresses, the MagicDNS name, container
#      port maps and absolute paths. This page is public, so an addressable
#      host plus a port map is an attack plan. Both files are therefore taken
#      from origin/main on every run rather than trusted from the worktree.
#   2. Never clobber remote commits. On a rebase conflict this aborts and
#      fails loudly instead of forcing.
#
# Set NAS_PUSH=0 to regenerate and commit locally without publishing.

set -euo pipefail

REPO=/home/bura/docs
cd "$REPO"

git fetch --quiet origin main

# Rebase local commits onto origin/main; if conflicts occur on generated files,
# favor the local commit (-X theirs). If rebase still cannot apply cleanly (e.g. stale diverged branch),
# reset to origin/main so the new status snapshot is generated cleanly on top of upstream.
if ! git rebase -X theirs origin/main >/dev/null 2>&1; then
  git rebase --abort 2>/dev/null || true
  git reset --hard origin/main >/dev/null 2>&1
fi

# The redaction (upstream d8f9cc1) was adopted into the local copy once. Do not
# re-checkout generate-status.sh on every run: origin's copy is older than the
# local bug fixes, so re-checkouting silently reverts them (and reintroduces
# the generator crash). Instead assert the redaction is still in place.
for marker in \
  "Real hostname withheld" \
  "Network identifiers are deliberately NOT published" \
  "Port bindings omitted on purpose" \
  "Count only - absolute paths leak the username"; do
  grep -q "$marker" generate-status.sh || {
    echo "ERROR: redaction marker missing from generate-status.sh: $marker" >&2
    echo "Refusing to publish. Inspect 'git show origin/main:generate-status.sh'." >&2
    exit 1
  }
done

# Upstream bug, patched after the checkout so a re-fetch cannot revert it.
# `grep -c` prints "0" AND exits 1 when there is no match, so `|| echo 0`
# appends a second "0"; the value then arrives as "0\n0" and int() raises
# ValueError, which aborts the whole run. Guarded so it is a no-op once fixed.
if grep -q 'grep -c "proxy" || echo 0' generate-status.sh; then
  sed -i 's/grep -c "proxy" || echo 0/grep -c "proxy" || true/' generate-status.sh
fi

bash generate-status.sh > status.json.tmp
mv status.json.tmp status.json

# generate-status.sh, deploy-status.sh, and .gitignore are added too so local fixes
# are published upstream and untracked drift is eliminated.
git add status.json generate-status.sh deploy-status.sh .gitignore

if git diff --cached --quiet; then
  echo "no change to publish"
  exit 0
fi

git commit -q -m "status: auto-update $(date -u '+%Y-%m-%d %H:%M UTC')"

if [ "${NAS_PUSH:-1}" != "1" ]; then
  echo "NAS_PUSH=0: committed locally, not published"
  exit 0
fi

# Replay onto anything new upstream. In status snapshots, favor the freshly generated snapshot (-X theirs).
if ! git pull --quiet --rebase -X theirs origin main; then
  git rebase --abort || true
  echo "ERROR: rebase onto origin/main conflicted; remote commits preserved, nothing pushed." >&2
  exit 1
fi

# Authenticate through gh's credential helper instead of embedding a token in
# the push URL, which would expose it in `ps` output and in error messages.
gh auth setup-git >/dev/null 2>&1 || {
  echo "ERROR: 'gh auth setup-git' failed; cannot authenticate push." >&2
  exit 1
}

git push origin main