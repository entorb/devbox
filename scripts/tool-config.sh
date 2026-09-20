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
