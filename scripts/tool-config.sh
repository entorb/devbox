#!/bin/sh
# Tools setup
# Two callers: the image build (seeds the home volume) and `devbox update`
# (re-asserts after ctx7, and repairs a volume seeded under an older home).

set -e
: "${HOME:=/home/t}"

# opencode.json:
#   instructions = .config/opencode/rules/agents.md
#   formatter = true

oc=$HOME/.config/opencode/opencode.json
[ -f "$oc" ] || echo '{}' >"$oc"
jq --arg p "$HOME/.config/opencode/rules/agents.md" \
  '.instructions = [$p] | .formatter = true' "$oc" >"$oc.new"
mv "$oc.new" "$oc"

# codegraph MCP (+ prompt hook for claude). Runs after the opencode.json step so it merges into
# that file instead of creating opencode.jsonc. Re-runs are no-ops. Needs the image's codegraph.
codegraph install -t claude,opencode -l global -y </dev/null

# codegraph and ctx7 re-add long instructions on every run; their MCP servers already carry them.
# Runs after both (ctx7 setup precedes tool-config in both callers). Markers stay, so the tools
# keep updating their block in place and the next run shrinks it again.
shrink() { # shrink <file> <start-marker> <end-marker> <line>
  [ -f "$1" ] || return 0
  awk -v s="$2" -v e="$3" -v l="$4" '
    !skip && $0 == s { print; print l; skip = 1; next }
    skip && $0 == e { skip = 0 }
    !skip' "$1" >"$1.new" && mv "$1.new" "$1"
}
# keep tool + CLI names: this block is how subagents and non-MCP harnesses learn codegraph
# shellcheck disable=SC2016  # literal backticks, markdown not command substitution
cg='Repos with `.codegraph/`: `codegraph_explore` (MCP) or `codegraph explore "<query>"` (shell) before grep/Read; no index: skip (indexing is the user'"'"'s decision).'
# opencode prefixes the MCP server key to tool names
# shellcheck disable=SC2016  # as above
cg_oc='Repos with `.codegraph/`: `codegraph_codegraph_explore` (MCP) or `codegraph explore "<query>"` (shell) before grep/Read; no index: skip (indexing is the user'"'"'s decision).'
c7='Context7 for library docs when an API is new to the code or a version changes; not for APIs the code already uses.'
shrink "$HOME/.claude/CLAUDE.md" '<!-- CODEGRAPH_START -->' '<!-- CODEGRAPH_END -->' "$cg"
shrink "$HOME/.config/opencode/AGENTS.md" '<!-- CODEGRAPH_START -->' '<!-- CODEGRAPH_END -->' "$cg_oc"
shrink "$HOME/.config/opencode/AGENTS.md" '<!-- context7 -->' '<!-- context7 -->' "$c7"
[ ! -f "$HOME/.claude/rules/context7.md" ] || echo "$c7" >"$HOME/.claude/rules/context7.md"

# git identity, handed in by `devbox update` from the host's global config. Unset at image build,
# so that caller skips it. user.name/user.email cover author and committer both, which the
# GIT_COMMITTER_* the launcher would otherwise have to pass do not do on their own.
if [ -n "${GIT_AUTHOR_NAME:-}" ] && [ -n "${GIT_AUTHOR_EMAIL:-}" ]; then
  git config --global user.name "$GIT_AUTHOR_NAME"
  git config --global user.email "$GIT_AUTHOR_EMAIL"
fi

# The box's own venv dir. uv puts it at <repo>/.venv-box (UV_PROJECT_ENVIRONMENT), inside a
# bind-mounted host repo, so it must stay out of git without editing every repo's .gitignore.
# ~/.config/git/ignore is git's default excludesFile, no core.excludesFile needed.
gi=$HOME/.config/git/ignore
mkdir -p "$(dirname "$gi")"
[ -f "$gi" ] || : >"$gi"
grep -qx '\.venv-box/' "$gi" || echo '.venv-box/' >>"$gi"
