#!/usr/bin/env sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
artifact="$repo_root/docs/artifact_v1_contract.md"
adapter="$repo_root/docs/host_adapter_v1_contract.md"

[ -f "$artifact" ] || {
  echo "missing docs/artifact_v1_contract.md" >&2
  exit 1
}

[ -f "$adapter" ] || {
  echo "missing docs/host_adapter_v1_contract.md" >&2
  exit 1
}

grep -q '^# ArtifactV1 Contract$' "$artifact"
grep -q '^## Binary Layout$' "$artifact"
grep -q '^## Canonical Encoding$' "$artifact"
grep -q '^## Capability Manifest$' "$artifact"
grep -q '^## Requirement Table$' "$artifact"
grep -q '^## Canonical Hashing$' "$artifact"
grep -q '^## Reserved Versioning Space$' "$artifact"
grep -q 'not the current `ProgramPlan` JSON surface' "$artifact"
grep -q 'ASCII `SFTARTV1`' "$artifact"
grep -q 'must be `72`' "$artifact"
grep -q 'Blake3-256' "$artifact"
grep -q 'build_fingerprint_blake3_256' "$artifact"
grep -q 'tool.call' "$artifact"
grep -q 'tool-only' "$artifact"
grep -q 'capability_id` links each lowered requirement' "$artifact"

grep -q '^# HostAdapterV1 Contract$' "$adapter"
grep -q '^## Request ID Discipline$' "$adapter"
grep -q '^## Common Envelope$' "$adapter"
grep -q '^## Tool Contract$' "$adapter"
grep -q '^## Reserved Future Expansion$' "$adapter"
grep -q '^## Sync Semantics$' "$adapter"
grep -q '^## Failure Model$' "$adapter"
grep -q 'tool-only' "$adapter"
grep -q '<authority>/<name>@v<major>' "$adapter"
grep -q 'only one request may be outstanding at a time in v1' "$adapter"
grep -q 'HostAdapterV1 never throws hidden host exceptions' "$adapter"
grep -q 'control: enum { resume, return_now, abort }' "$adapter"
