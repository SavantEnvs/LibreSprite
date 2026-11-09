# syntax=docker/dockerfile:1.7
#
# Commit-image Dockerfile (SMALL form, PREFERRED) — builds ON TOP of the org C/C++ base
# image (ghcr.io/savantenvs/base). The base already provides debian + clang/llvm +
# libFuzzer/afl++ + the identities + the build-contract ENV, so this only adds the
# per-commit build (built on top of the prebuilt base, rather than building the toolchain in-image).
#
# Build (from the repo root):
#   DOCKER_BUILDKIT=1 docker build -f mayhem/Dockerfile \
#       --build-arg COMMIT=$(git rev-parse HEAD) \
#       [--build-arg SOURCE_DATE_EPOCH=$(date +%s)] \
#       -t mytag .

# The org base, pinned to a fixed DATE-tagged base (YYYYMMDD; shared by all integrations
# minted against it). Use the current dated tag; pin by digest in production: ...base@sha256:<digest>.
FROM ghcr.io/savantenvs/base:20261023

ARG COMMIT
ARG REPO_URL
# SOURCE_DATE_EPOCH stays an ARG (available to build.sh); do NOT bake it as an ENV — an
# empty value breaks clang ("must be a non-negative decimal integer") both here and for
# any in-image rebuild. build.sh unsets it when empty.
ARG SOURCE_DATE_EPOCH

# Sanitizer override: the base exports SANITIZER_FLAGS (ASan+UBSan, halting) as the default.
# To change it for a build (e.g. ASan-only, or add MSan): --build-arg SANITIZER_FLAGS="...".
# Declare it WITHOUT a default (no '='): an undefaulted ARG lets the base ENV flow through to
# build.sh when not passed, and an explicit --build-arg overrides it. (An empty default — `=` —
# would instead shadow the base ENV and silently wipe the sanitizers.)
ARG SANITIZER_FLAGS
# Coverage (optional, off by default): instrument the TEST build to measure how much of the project
# the suite exercises — --build-arg COVERAGE_FLAGS="-fprofile-instr-generate -fcoverage-mapping".
# Empty by default (no effect on the normal oracle build); build.sh appends it to the test build only.
ARG COVERAGE_FLAGS=
# Build parallelism (optional). build.sh falls back to nproc when unset: --build-arg MAYHEM_JOBS=8
ARG MAYHEM_JOBS=

# LibreSprite needs the SDL2/image/font/compression dev packages from apt, plus gtest for the unit tests.
USER root
RUN [ -n "$SOURCE_DATE_EPOCH" ] && repro-sources-list.sh || true ; \
    apt-get update && apt-get install -yq --no-install-recommends \
        ninja-build pkg-config libgtest-dev zlib1g-dev libpng-dev libjpeg-dev libgif-dev libwebp-dev \
        libfreetype-dev libpixman-1-dev libtinyxml2-dev libarchive-dev libssl-dev libsdl2-dev \
        libsdl2-image-dev libx11-dev libxext-dev libxcursor-dev libxi-dev libxxf86vm-dev libsm-dev \
        libice-dev libxcb1-dev \
 && rm -rf /var/lib/apt/lists/*

# Everything the upstream build would download is fetched here once, from a pinned release/commit with a
# sha256, into /opt/toolchains/deps/<name>-<version>/ (SPEC §6.2 item 19). build.sh never touches the
# network: it points at these. cmake >= 4.1 is required by the project (the base ships older); flic and
# simpleini are git submodules, which a Docker build context does not populate.
ARG CMAKE_VER=4.4.3
ARG CMAKE_SHA256=d6c83076c575bc00b823522ac974bda66d0af05d6ddc30e739c12385cf32c6cc
ARG FLIC_REV=876ef60df5fec606f8eb0638ee893e4967db4673
ARG FLIC_SHA256=e66ab8d28c630a80a2be2baf260f87481ca7b0d35101e74b3ef131f47989d1a9
ARG SIMPLEINI_REV=c94997d4d64394833e4b9d21f4573c66600c9a9a
ARG SIMPLEINI_SHA256=46ae433ddd4fcec9cf8da3f689a901af8a45e3d06327b82934a2821f945a59ba
RUN set -e; \
    d=/opt/toolchains/deps/cmake-${CMAKE_VER}; mkdir -p "$d"; \
    curl -fsSL -o /tmp/dep.tgz https://github.com/Kitware/CMake/releases/download/v${CMAKE_VER}/cmake-${CMAKE_VER}-linux-x86_64.tar.gz; \
    echo "${CMAKE_SHA256}  /tmp/dep.tgz" | sha256sum -c -; \
    tar -xzf /tmp/dep.tgz --strip-components=1 -C "$d"; \
    d=/opt/toolchains/deps/flic-${FLIC_REV%${FLIC_REV#???????}}; mkdir -p "$d/src"; \
    curl -fsSL -o /tmp/dep.tgz https://github.com/aseprite/flic/archive/${FLIC_REV}.tar.gz; \
    echo "${FLIC_SHA256}  /tmp/dep.tgz" | sha256sum -c -; \
    tar -xzf /tmp/dep.tgz --strip-components=1 -C "$d/src"; \
    d=/opt/toolchains/deps/simpleini-${SIMPLEINI_REV%${SIMPLEINI_REV#???????}}; mkdir -p "$d/src"; \
    curl -fsSL -o /tmp/dep.tgz https://github.com/aseprite/simpleini/archive/${SIMPLEINI_REV}.tar.gz; \
    echo "${SIMPLEINI_SHA256}  /tmp/dep.tgz" | sha256sum -c -; \
    tar -xzf /tmp/dep.tgz --strip-components=1 -C "$d/src"; \
    rm -f /tmp/dep.tgz; chmod -R a+rX /opt/toolchains/deps
USER mayhem

# Source enters from the build CONTEXT (the CI checkout): the FULL repo (incl. .git
# history) is copied to /mayhem as `mayhem`; build.sh builds in place.
USER mayhem
WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

# Anything a Dockerfile step materializes into the tree (downloaded fixtures, generated headers,
# vendored deps) MUST be committed or (re)created by build.sh: rlenv's patch grader runs
# `git clean -ffdX` before every graded build, so a gitignored, untracked file is gone by then and
# every honest patch scores zero (SPEC §6.2 item 16; verify-repo.sh checks it).
#
# OPTIONAL compile-cache pre-fill (SPEC §6.2 item 18). Bases minted with /opt/mayhem/ccache/prefill
# run the build under rlenv's pinned ccache, so the patch grader's first (otherwise cold) rebuild is
# warm — this is what keeps large C/C++ targets inside the build time limit. Older bases fall back to
# the plain build; a missing or stale pre-fill only costs a cold cache. Never enable ccache in
# build.sh or via ENV/PATH, and keep the compiler resolving by name (CC=clang) or nothing is cached.
RUN if [ -x /opt/mayhem/ccache/prefill ]; then /opt/mayhem/ccache/prefill bash mayhem/build.sh; \
    else bash mayhem/build.sh; fi

# Run the project's functional tests at build time IF the repo ships them (mayhem/test.sh is
# optional — omit it only when the repo has no tests meaningful for RL). A failing suite fails the
# image build, so the commit image is guaranteed to build AND pass its own tests.
RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh — repo ships no functional tests"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
