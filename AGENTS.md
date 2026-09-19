# DevBox

Guide to this repo. Working conventions (commit format, caveman speech, lazy-senior mode) live in
`AGENTS.md-TEMPLATE` — that file is not about this repo, it is the rule file mounted into every box.

## What this repo is

A launcher plus an image. `./devbox` starts a throwaway container that sees only the repos listed in
`repos.conf`, nothing else of the host. `README.md` is the user-facing doc; keep it in sync with
behavior changes.

| File                 | Role                                                                    |
| -------------------- | ----------------------------------------------------------------------- |
| `devbox`             | bash launcher: subcommands, `--port` parsing, mounts, `docker run` flags |
| `Dockerfile`         | the image: apt packages, node/uv, CLI tools, playwright, user `t`        |
| `scripts/tool-config.sh` | seeds/repairs volume-side config; run at build **and** by `devbox update` |
| `AGENTS.md-TEMPLATE` | mounted read-only into both agents' rules dirs inside the box            |
| `repos.conf`, `.env` | local, gitignored; `*.EXAMPLE` are the committed stand-ins               |
| `scripts/chk_*.sh`   | checks, all run by `scripts/run_checks.sh`                               |

## Invariants — break these and the box misbehaves quietly

- **An existing `devbox-home` volume is never reseeded.** Anything the Dockerfile writes under
  `/home/t` reaches only first-time users. New config for existing boxes goes into
  `scripts/tool-config.sh`, which `./devbox update` re-runs.
- **What must survive `./devbox reset` goes to `/usr/local` or `/opt`**, root-owned. Only the two
  agents live in the volume (`~/.npm-global`), so their own updaters can replace them.
- **No host secrets pass in.** No ssh agent, no docker socket, no provider keys, no host env.
  `CONTEXT7_KEY` is the single exception and only on `./devbox update`.
- **Nothing is version-pinned in the `Dockerfile`** on purpose: `./devbox build --no-cache --pull`
  is the update path.
- No `sudo` inside, `--cap-drop ALL --security-opt no-new-privileges`. Keep it that way.
- Ports publish 1:1 on `127.0.0.1` only, never the LAN, and nothing is published by default.
- **Host deps and box deps never share a directory.** The box's venv is `.venv-box`
  (`UV_PROJECT_ENVIRONMENT` in the `Dockerfile`), and every repo with a `package.json` gets a
  `devbox-nm-<repo>` volume mounted over its `node_modules`. Both sides install once, neither
  clobbers the other's platform binaries.
- Build-time commands that could prompt need their non-interactive flag plus `</dev/null`
  (`rtk init --auto-patch`, `ctx7 setup --oauth -y`) — a prompt hangs the build.

## Checks

```sh
./devbox selftest        # --port parsing, no docker needed; extend it when touching that code
sh scripts/run_checks.sh # prek (rumdl, shfmt, shellcheck, gitleaks, ...) + cspell
```

Unknown words land in `cspell-words-missing.txt`; fix the typo or move append word into
`cspell-words.txt` (auto-sorted by prek).

Touching the image means `./devbox build` before claiming it works; a container run is the only
real test of `docker run` flag changes.
