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
