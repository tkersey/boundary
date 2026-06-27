# Boundary v0 Compatibility Policy

Boundary v0 freezes the language/profile side of the platform contract.

Patch releases may fix validators, reject malformed inputs that should always have been invalid, improve performance, and add diagnostics. They must preserve valid v0 encodings and fingerprints.

Minor releases may add optional features and new format versions. They must not silently change existing format versions.

Major releases may break compatibility intentionally with explicit documentation.

Hard rules:
- enum ordinal changes require a version bump;
- canonical field-order changes require a version bump;
- fingerprint-domain changes require a fingerprint-version bump;
- ABI signature changes require the consuming runtime ABI to bump;
- a Boundary dependency upgrade requires World compatibility proof;
- retained old conformance corpora remain compatibility evidence.
