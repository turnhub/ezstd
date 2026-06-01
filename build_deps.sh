#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
DEPS_DIR="_build/deps"
OS="$(uname -s)"
KERNEL=$(echo $(lsb_release -ds 2>/dev/null || cat /etc/*release 2>/dev/null | head -n1 | awk '{print $1;}') | awk '{print $1;}')
CPUS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu)"

# Zstandard configuration
# https://github.com/facebook/zstd.git

ZSTD_REPO="https://github.com/facebook/zstd.git"
ZSTD_BRANCH="release"
# Tags are mutable: upstream could re-point v1.5.7 at a malicious commit and we
# would build it unknowingly. The pinned commit SHA below is the source of
# truth for what we actually build; ZSTD_TAG is kept only for readability and
# is verified against the SHA before building (see checkout_lib).
# ZSTD_SHA is the commit that v1.5.7 currently resolves to:
#   git ls-remote https://github.com/facebook/zstd.git 'v1.5.7^{}'
ZSTD_TAG="v1.5.7"
ZSTD_SHA="f8745da6ff1ad1e7bab384bd1f9d742439278e99"
ZSTD_DIR="zstd"
ZSTD_SUCCESS_FILE="lib/libzstd.a"

fail_check() {
    "$@"
    local status=$?
    if [ $status -ne 0 ]; then
        echo "❌ Error running command: $*" >&2
        exit $status
    fi
}

checkout_lib() {
    local repo_url="$1"
    local sha="$2"
    local tag="$3"
    local branch="$4"
    local dir_name="$5"
    local success_file="$6"

    local full_path="$DEPS_DIR/$dir_name/$success_file"
    if [ -f "$full_path" ]; then
        echo "✅ $dir_name already exists at $full_path"
        echo "   To rebuild, delete: $DEPS_DIR/$dir_name"
        return
    fi

    echo "📦 Cloning $repo_url (branch: $branch, pinned commit: $sha)"

    mkdir -p "$DEPS_DIR"
    pushd "$DEPS_DIR" > /dev/null

    if [ ! -d "$dir_name" ]; then
        fail_check git clone --branch "$branch" "$repo_url" "$dir_name"
    fi

    pushd "$dir_name" > /dev/null

    # Make sure the exact pinned commit is present locally. Cloning the branch
    # normally fetches it (it is reachable from the release tag), but fetch it
    # explicitly as a fallback so we never silently fall back to whatever the
    # branch currently happens to point at.
    if ! git cat-file -e "${sha}^{commit}" 2>/dev/null; then
        fail_check git fetch origin "$sha"
    fi

    # Supply-chain safety: tags are mutable. If the human-readable tag is
    # present, confirm it still resolves to the commit we pinned. A mismatch
    # means upstream moved the tag (re-tagged) and we must refuse to build.
    local tag_sha
    tag_sha="$(git rev-list -n 1 "$tag" 2>/dev/null || true)"
    if [ -n "$tag_sha" ] && [ "$tag_sha" != "$sha" ]; then
        echo "❌ Supply-chain check failed for $dir_name" >&2
        echo "   Tag '$tag' now resolves to $tag_sha" >&2
        echo "   but the build is pinned to    $sha" >&2
        echo "   The upstream tag appears to have been moved. Refusing to build." >&2
        echo "   If this change is expected, update ZSTD_SHA in build_deps.sh." >&2
        exit 1
    fi

    # Check out the pinned commit by SHA (detached HEAD) rather than the tag,
    # so the build is reproducible and independent of tag mutations.
    fail_check git checkout --quiet "$sha"

    # Belt and braces: confirm HEAD really is the pinned commit.
    local head_sha
    head_sha="$(git rev-parse HEAD)"
    if [ "$head_sha" != "$sha" ]; then
        echo "❌ Expected HEAD to be $sha but got $head_sha" >&2
        exit 1
    fi
    echo "🔒 Checked out pinned commit $sha ($tag)"

    build_library "$dir_name"
    popd > /dev/null
    popd > /dev/null
}

build_library() {
    local dir="$1"
    echo "🔧 Building $dir"

    if [[ -z "${NO_CMAKE:-}" ]] && command -v cmake >/dev/null 2>&1; then
        echo "   ➤ Using CMake..."
        cmake -S build/cmake -DZSTD_BUILD_PROGRAMS=OFF -DZSTD_LEGACY_SUPPORT=OFF
        fail_check make libzstd_static -j "$CPUS"
    else
        echo "   ➤ Using Make directly..."
        export CFLAGS="${CFLAGS:--O2}"

        if [[ "$OS" == "Linux" ]]; then
            export CFLAGS="$CFLAGS -fPIC"
            export CXXFLAGS="${CXXFLAGS:-} -fPIC"
        fi

        fail_check make lib-release -j "$CPUS"

        # Remove shared libs to ensure a static-only build
        rm -f lib/*.so lib/*.so.* lib/*.dylib
    fi
}

echo "🖥️  Detected system configuration:"
echo "   ➤ OS Type   : $OS"
echo "   ➤ OS Name   : $KERNEL"
echo "   ➤ CPU Cores : $CPUS"

checkout_lib "$ZSTD_REPO" "$ZSTD_SHA" "$ZSTD_TAG" "$ZSTD_BRANCH" "$ZSTD_DIR" "$ZSTD_SUCCESS_FILE"
