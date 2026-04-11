#!/usr/bin/env sh
set -eu

native_bin="$1"
wasm_bin="$2"

native_out="$(mktemp "${TMPDIR:-/tmp}/artifact-vm-native.XXXXXX")"
wasm_out="$(mktemp "${TMPDIR:-/tmp}/artifact-vm-wasm.XXXXXX")"
trap 'rm -f "$native_out" "$wasm_out"' EXIT INT TERM

"$native_bin" >"$native_out"
wasmtime run "$wasm_bin" >"$wasm_out"

diff -u "$native_out" "$wasm_out"
