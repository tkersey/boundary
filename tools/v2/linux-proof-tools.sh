#!/bin/sh
# Reproducible proof-tool acquisition; never used by compiler/data consumers.
set -eu
if [ "$(uname -s)/$(uname -m)" != Linux/x86_64 ]; then
    echo 'proof tools require Linux x86-64' >&2
    exit 2
fi
for utility in curl sha256sum tar xz zstd; do
    command -v "$utility" >/dev/null || { echo "missing proof setup tool: $utility" >&2; exit 2; }
done
proof_tools_root="${BOUNDARY_PROOF_TOOLS:-$PWD/.cache/proof-tools/linux-x86_64}"
mkdir -p "$proof_tools_root/archives" "$proof_tools_root/bin"
proof_tools_root="$(cd "$proof_tools_root" && pwd)"

fetch() {
    proof_archive="$proof_tools_root/archives/$1"
    if [ ! -f "$proof_archive" ]; then
        curl --fail --location --retry 3 "$2" -o "$proof_archive.pending"
        printf '%s  %s\n' "$3" "$proof_archive.pending" | sha256sum --check --status
        mv "$proof_archive.pending" "$proof_archive"
    fi
    printf '%s  %s\n' "$3" "$proof_archive" | sha256sum --check --status
}

fetch lean-4.33.1-linux.tar.zst \
    https://github.com/leanprover/lean4/releases/download/v4.33.1/lean-4.33.1-linux.tar.zst \
    890afd185370f85666025b883914ab4f4b339136f8c96167b69cfb62aecaf235
fetch zig-x86_64-linux-0.16.0.tar.xz \
    https://ziglang.org/download/0.16.0/zig-x86_64-linux-0.16.0.tar.xz \
    70e49664a74374b48b51e6f3fdfbf437f6395d42509050588bd49abe52ba3d00
fetch node-v26.8.1-linux-x64.tar.xz \
    https://nodejs.org/dist/v26.8.1/node-v26.8.1-linux-x64.tar.xz \
    3e301118d7df53d563b7e96c1617545f26e2f76f9724be668d6cab65c15dda5d

# Extraction is always from an authenticated archive, into a fresh directory.
# Cached executable substitutions therefore cannot survive tool installation.
proof_extract="$(mktemp -d "$proof_tools_root/extract.XXXXXX")"
trap 'rm -rf "$proof_extract"' EXIT HUP INT TERM
tar --zstd -xf "$proof_tools_root/archives/lean-4.33.1-linux.tar.zst" -C "$proof_extract"
tar -xJf "$proof_tools_root/archives/zig-x86_64-linux-0.16.0.tar.xz" -C "$proof_extract"
tar -xJf "$proof_tools_root/archives/node-v26.8.1-linux-x64.tar.xz" -C "$proof_extract"
for distribution in lean-4.33.1-linux zig-x86_64-linux-0.16.0 node-v26.8.1-linux-x64; do
    rm -rf "$proof_tools_root/$distribution"
    mv "$proof_extract/$distribution" "$proof_tools_root/$distribution"
done
for executable in lean lake leanchecker; do
    ln -sf "$proof_tools_root/lean-4.33.1-linux/bin/$executable" "$proof_tools_root/bin/$executable"
done
ln -sf "$proof_tools_root/zig-x86_64-linux-0.16.0/zig" "$proof_tools_root/bin/zig"
ln -sf "$proof_tools_root/node-v26.8.1-linux-x64/bin/node" "$proof_tools_root/bin/node"
"$proof_tools_root/bin/lean" --version
"$proof_tools_root/bin/zig" version
"$proof_tools_root/bin/node" --version
sha256sum "$proof_tools_root/lean-4.33.1-linux/bin/leanchecker"
printf 'proof_tool_bin=%s/bin\n' "$proof_tools_root"
