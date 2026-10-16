#!/usr/bin/env bash
# Ports one Adobe isolated security archive to one release-line branch and opens a
# PR for it. Called by .github/workflows/port-security-patch.yml; runnable locally
# with DRY_RUN=1, which stops before push and prints the PR body.
#
# Inputs (environment):
#   LABEL      bulletin or archive id, e.g. apsb26-153
#   BRANCH     line branch, e.g. main or release/2.x
#   ARCHIVE    archive name without .zip, e.g. 2-4-9-oct-2026
#   BULLETIN   optional bulletin URL for the PR body
#   PORTER     path to a generate-mirror-repo-js checkout with node_modules
#   REPOS      directory holding this checkout as mageos-magento2 plus the
#              separately built repositories, passed as --gitRepoDir
#   WORK       scratch directory; the Adobe archive is unpacked here and never committed
#   GH_REPO    owner/repo the PR is opened against

set -euo pipefail

[[ "$LABEL" =~ ^[a-z0-9][a-z0-9-]{0,40}$ ]] || { echo "::error::bad label: $LABEL"; exit 1; }
[[ "$BRANCH" =~ ^(main|release/[0-9]+\.x)$ ]] || { echo "::error::bad branch: $BRANCH"; exit 1; }
[[ "$ARCHIVE" =~ ^[0-9]+-[0-9]+-[0-9]+(-p[0-9]+)?-[a-z]{3}-[0-9]{4}$ ]] || { echo "::error::bad archive: $ARCHIVE"; exit 1; }

REPO_DIR="$REPOS/mageos-magento2"
TOOL_BRANCH="${LABEL}-${BRANCH//\//-}"
PR_BRANCH="security/${TOOL_BRANCH}"
ARCHIVE_URL="https://repo.magento.com/patch/${ARCHIVE}.zip"
REPORT="$WORK/port.json"

if [ -z "${DRY_RUN:-}" ] && git -C "$REPO_DIR" ls-remote --exit-code --heads origin "$PR_BRANCH" >/dev/null 2>&1; then
  echo "::notice::$PR_BRANCH already exists; not porting again"
  exit 0
fi

mkdir -p "$WORK/adobe"
curl -sSf -A 'mage-os-security-watch (+https://github.com/mage-os/security-watch)' \
  -o "$WORK/adobe/$ARCHIVE.zip" "$ARCHIVE_URL"
unzip -qo "$WORK/adobe/$ARCHIVE.zip" -d "$WORK/adobe/$ARCHIVE"
PATCH=$(find "$WORK/adobe/$ARCHIVE" -name '*-CE.patch' ! -path '*__MACOSX*' | head -1)
[ -n "$PATCH" ] || { echo "::error::no -CE.patch in $ARCHIVE_URL"; exit 1; }
PATCH_NAME=$(basename "$PATCH")

run_port() {
  (cd "$PORTER" && node bin/apply-security-patch.js \
    --repoDir="$REPO_DIR" --gitRepoDir="$REPOS" --patch="$PATCH" \
    --label="$LABEL" --branches="$BRANCH" --report="$REPORT" --force "$@") || true
}
status() { node -p "JSON.parse(require('fs').readFileSync('$REPORT','utf8')).results[0].status"; }
detail() { node -p "JSON.parse(require('fs').readFileSync('$REPORT','utf8')).results[0].detail"; }

run_port
STATUS=$(status)
# A rejected port rolls back to nothing. Rerunning with --partial gives the reviewer
# everything that did apply, and the rejected files are named in the PR.
if [ "$STATUS" = "REJECTED" ]; then
  FIRST_DETAIL=$(detail)
  run_port --partial
  STATUS=$(status)
fi
DETAIL=$(detail)
echo "port: $STATUS — $DETAIL"

if ! git -C "$REPO_DIR" rev-parse --verify -q "refs/heads/$TOOL_BRANCH" >/dev/null; then
  echo "::error::no branch produced ($STATUS: $DETAIL)"
  exit 1
fi

# .rej files hold Adobe's hunks. They are listed by name only and deleted, because
# their content is Adobe's patch text and must not be published.
REJECTS=$(cd "$REPO_DIR" && git ls-files --others --exclude-standard -- '*.rej' | sed 's/\.rej$//')
(cd "$REPO_DIR" && git ls-files --others --exclude-standard -z -- '*.rej' | xargs -0 rm -f)

CHANGED=$(git -C "$REPO_DIR" diff --name-only "$BRANCH" "$TOOL_BRANCH")
LINT_FAILS=""
MARKERS=""
git -C "$REPO_DIR" checkout -q "$TOOL_BRANCH"
while IFS= read -r file; do
  [ -f "$REPO_DIR/$file" ] || continue
  if grep -qE '^(<<<<<<<|>>>>>>>)( |$)' "$REPO_DIR/$file"; then MARKERS+="$file"$'\n'; fi
  if [[ "$file" == *.php ]] && ! php -l "$REPO_DIR/$file" >/dev/null 2>&1; then LINT_FAILS+="$file"$'\n'; fi
done <<< "$CHANGED"
git -C "$REPO_DIR" checkout -q "$BRANCH"

READY=1
[ "$STATUS" = "CLEAN" ] || READY=0
[ -z "$MARKERS$LINT_FAILS" ] || READY=0

as_list() { if [ -n "$1" ]; then printf '%s\n' "$1" | sed '/^$/d; s/.*/- `&`/'; else echo "- none"; fi; }

BODY="$WORK/pr-body.md"
{
  echo "Automated port of Adobe's \`$PATCH_NAME\` (from \`$ARCHIVE.zip\`) to \`$BRANCH\`."
  [ -n "${BULLETIN:-}" ] && echo "Bulletin: $BULLETIN"
  echo
  echo "| Result | |"
  echo "|---|---|"
  echo "| Status | **$STATUS** |"
  echo "| Detail | $DETAIL |"
  [ -n "${FIRST_DETAIL:-}" ] && echo "| Without \`--partial\` | $FIRST_DETAIL |"
  echo "| Files changed | $(printf '%s\n' "$CHANGED" | sed '/^$/d' | wc -l | tr -d ' ') |"
  echo
  echo "**Rejected, needs porting by hand:**"
  as_list "$REJECTS"
  echo
  echo "**Conflict markers** (grep, not lint: markers inside docblocks pass \`php -l\`):"
  as_list "$MARKERS"
  echo
  echo "**PHP lint failures:**"
  as_list "$LINT_FAILS"
  echo
  if [ "$READY" = 1 ]; then
    echo "Applied cleanly. Review as you would any security change before merging."
  else
    echo "Opened as a draft: finish the files above, push to this branch, then mark ready."
  fi
  echo
  echo "Adobe's patch file is not committed or attached; only the translated change to this tree is."
} > "$BODY"

if [ -n "${DRY_RUN:-}" ]; then
  echo "DRY_RUN: would push $TOOL_BRANCH as $PR_BRANCH and open PR (ready=$READY)"
  cat "$BODY"
  exit 0
fi

git -C "$REPO_DIR" push -q origin "refs/heads/${TOOL_BRANCH}:refs/heads/${PR_BRANCH}"
DRAFT=()
[ "$READY" = 1 ] || DRAFT=(--draft)
gh pr create --repo "$GH_REPO" --base "$BRANCH" --head "$PR_BRANCH" "${DRAFT[@]}" \
  --title "Port Adobe security patch ${LABEL} to ${BRANCH} (${STATUS})" \
  --body-file "$BODY"
