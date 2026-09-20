# syntax=docker/dockerfile:1

# Everything is installed inside the image at its latest version when build.
# Nothing from the host is mounted in: rebuild to update (docker build --no-cache --pull).

ARG NODE_MAJOR=24
ARG UBUNTU_VERSION=26.04

#
# => helper stages, only copied from
#

FROM ghcr.io/astral-sh/uv:latest AS uv
FROM node:${NODE_MAJOR}-trixie-slim AS node

FROM ubuntu:${UBUNTU_VERSION}

#
# => Base apt packages
#

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      curl \
      fd-find \
      file \
      git \
      htop \
      imagemagick \
      jq \
      less \
      librsvg2-bin \
      mc \
      ncdu \
      netcat-openbsd \
      openssh-client \
      python3 \
      python3-dev \
      ripgrep \
      rsync \
      shellcheck \
      sqlite3 \
      tree \
      unzip \
      vim

RUN rm -rf /var/lib/apt/lists/*

# the binary is fdfind on debian/ubuntu (name clash with fdclone); agents and muscle memory say fd
RUN ln -s /usr/bin/fdfind /usr/local/bin/fd

#
# => Env vars
#

# set before the installs below: npm_config_update_notifier and UV_LINK_MODE steer them,
# UV_TOOL_DIR keeps the tool venvs out of the resettable home volume
ENV LANG=C.UTF-8 \
    npm_config_update_notifier=false \
    UV_LINK_MODE=copy \
    UV_TOOL_DIR=/opt/uv-tools

#
# => Copy node from official node image
#

# node from the official image, same deal as uv: apt ships v22 + npm 9, NodeSource means one
# more apt repo to trust, and the tarball route means hand-rolled arch detection plus a sha check.
# Binary and npm only -- that image also carries yarn and corepack, neither of which is wanted.
# Its glibc is older than this base's, which is the direction that works.
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/npm
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
 && ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
 && node --version

#
# => Copy uv from official uv image
#
COPY --from=uv /uv /uvx /usr/local/bin/

#
# => npm 12, pnpm, biome via npm
#

# root-owned in /usr/local: the unprivileged user cannot overwrite these. The two agents are
# deliberately NOT here -- they go into the home volume below so they can update themselves.
# npm 12 blocks dependency lifecycle scripts by default; --allow-scripts opts pnpm back in
# (node 24 still ships npm 11, where the flag is silently ignored -- hence the explicit upgrade)
RUN npm install -g npm@12 \
 && npm install -g --allow-scripts=pnpm \
      pnpm \
      @biomejs/biome \
 && npm cache clean --force

#
# => ruff, prek, rumdl via uv
#

# python-based CLIs into /usr/local so they survive a home-volume reset, unlike ~/.local/bin
RUN UV_TOOL_BIN_DIR=/usr/local/bin uv tool install prek \
 && UV_TOOL_BIN_DIR=/usr/local/bin uv tool install rumdl \
 && UV_TOOL_BIN_DIR=/usr/local/bin uv tool install ruff

#
# => rtk via install.sh
#

# upstream installer: verifies the release sha256 and rejects unsafe archive paths.
# RTK_INSTALL_DIR keeps it root-owned in /usr/local/bin, out of the resettable home volume.
RUN curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh \
      | RTK_INSTALL_DIR=/usr/local/bin sh \
 && chown root:root /usr/local/bin/rtk \
 && rtk --version

#
# => playwright + headless chromium
#

# browsers go to /opt, not the home volume: an existing volume is never reseeded, so a
# ~/.cache install would be missing for everyone who already has one. t owns the dir so
# `npx playwright install firefox` still works inside without sudo (by uid: the rename to t
# happens further down, the name does not exist yet here) -- though /opt is container-local,
# so an extra browser meant to stick wants PLAYWRIGHT_BROWSERS_PATH in the home volume.
# --only-shell: chromium-headless-shell only -- there is no display in here, and the full
# Chromium build is twice the size. Tests must leave `channel` unset to use it.
# --with-deps shells out to apt-get install without an update first, hence the update here.
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright
RUN apt-get update \
 && npx -y playwright@latest install --with-deps --only-shell chromium \
 && chown -R 1000:1000 /opt/ms-playwright \
 && rm -rf /var/lib/apt/lists/* /root/.npm

#
# => copy tool setup script
#

# shared with `devbox update`: one copy of the config that rtk and ctx7 do not own
COPY --chmod=755 scripts/tool-config.sh /usr/local/bin/tool-config

#
# => setup user t (renamed from ubuntu)
#

# these must exist and be t-owned before the launcher mounts AGENTS.md-TEMPLATE into the rules dirs,
# otherwise docker creates them root-owned and the agents cannot write their own state
# uid/gid stay 1000 -- only the names and the home path change, so bind-mounted files keep the
# same ownership as on the host. -m moves the existing home, so nothing from the base image is lost.
RUN groupmod -n t ubuntu \
 && usermod -l t -d /home/t -m ubuntu

RUN mkdir -p /home/t/.config/opencode/rules /home/t/.claude/rules \
 && chown -R t:t /home/t \
 && gpasswd -d t sudo

# Agents live in the home volume, owned by t, so their own updaters can replace them in
# place. That survives a rebuild (the volume is not reseeded) and keeps logins and keys intact.
# The trade-off is deliberate: an agent here CAN overwrite its own install, unlike /usr/local.
ENV NPM_CONFIG_PREFIX=/home/t/.npm-global \
    PATH=/home/t/.npm-global/bin:$PATH

#
# => switch to user t and create dir /code
#

USER t
WORKDIR /code

#
# => user-level install of opencode and claude
#

RUN npm install -g --allow-scripts=@anthropic-ai/claude-code,opencode-ai \
      @anthropic-ai/claude-code \
      opencode-ai \
 && npm cache clean --force

#
# => user-level run of rtk and context7
# => "formatter = true" to OpenCode config
#

# Agent config is seeded into the image as t, so the devbox-home volume inherits it when
# docker first creates it. rtk and ctx7 own their own instructions -- RTK.md and the @RTK.md
# reference in CLAUDE.md, the ctx7 rule, skill and MCP config, the opencode plugin.
# AGENTS.md-TEMPLATE is mounted into the rules dirs at runtime, alongside these, so nothing here is shadowed.
# Flags are not optional: a bare `ctx7 setup` starts an interactive device login that blocks the
# build until the code expires. --oauth writes the endpoint and defers the login to first use.
# --auto-patch likewise: rtk otherwise prompts before adding its Bash hook to settings.json and
# </dev/null answers N, leaving the hook uninstalled and only a "MANUAL STEP" notice behind.
RUN rtk init --global --auto-patch </dev/null \
 && rtk init --global --opencode --auto-patch </dev/null \
 && pnpm dlx ctx7@latest setup --claude   --mcp --oauth -y </dev/null \
 && pnpm dlx ctx7@latest setup --opencode --mcp --oauth -y </dev/null \
 && tool-config \
 && rm -rf /home/t/.cache/pnpm

CMD ["bash"]
