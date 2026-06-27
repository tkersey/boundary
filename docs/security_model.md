# Boundary v0 Security Model

Trusted:
- selected runtime binary;
- selected Boundary package;
- selected World package when consuming World artifacts;
- receiver-local policy;
- receiver-owned actuators and effects.

Untrusted:
- module bytes;
- executable plan bytes;
- loaded value bytes;
- loaded session bytes;
- host claim metadata;
- sender permits and receipts as authority;
- storage contents.

Explicit non-claims:
- fingerprints are not signatures;
- receipts are not cryptographic attestations;
- retention acknowledgement is not durability proof;
- deterministic retry is not exactly-once;
- Archive valid-prefix recovery is not malicious-tamper protection;
- no confidentiality;
- no authenticity;
- no consensus;
- no revocation;
- no hostile-host protection.

Major threats:
- malformed binary input: invariant is total rejection without partial executable load; limit is the manifest budget set; rejection mode is malformed or unsupported; conformance cases cover malformed, trailing, excessive, forged, and unsupported vectors; remaining risk is implementation bugs outside retained vectors.
- feature confusion: invariant is unknown required features reject; optional features must be length-delimited and skippable; rejection mode is unsupported feature; conformance cases cover reachable and unreachable unsupported features; remaining risk is future formats that fail to bump their manifest version.
- authority confusion: invariant is host effects and credentials remain outside Boundary; limit is no host handles in semantic identity; rejection mode is absence from protocol manifest identity; conformance cases bind payload, result, and session bytes; remaining risk belongs to host policy.
