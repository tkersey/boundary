#!/usr/bin/env sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
cd "$repo_root"

tool="$repo_root/zig-out/bin/shift-durable-migrate"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/shift-durable-migrate.XXXXXX")"
manifest_path="$tmp_root/session.manifest.json"
events_path="$tmp_root/events.jsonl"
seed_json="$tmp_root/seed.json"
inspect_json="$tmp_root/inspect.json"
upgrade_json="$tmp_root/upgrade.json"
final_json="$tmp_root/final.json"
plan_seed_json="$tmp_root/plan-seed.json"
plan_inspect_json="$tmp_root/plan-inspect.json"
plan_upgrade_json="$tmp_root/plan-upgrade.json"
plan_final_json="$tmp_root/plan-final.json"
plan_manifest="$tmp_root/plan-session.manifest.json"
plan_events="$tmp_root/plan-events.jsonl"
nested_seed_json="$tmp_root/nested-seed.json"
nested_manifest="$tmp_root/deep/absolute/tree/session.manifest.json"
nested_events="$tmp_root/deep/absolute/tree/events.jsonl"

trap 'rm -rf "$tmp_root"' EXIT INT TERM

"$tool" seed \
  --manifest "$manifest_path" \
  --events "$events_path" \
  --scenario direct_return \
  >"$seed_json"

uv run python - <<'PY' "$seed_json"
import json, sys
data = json.load(open(sys.argv[1]))
assert data["command"] == "seed"
assert data["status"] == "exact_replay"
assert data["scenario_id"] == "direct_return"
assert data["migration_report"] is None
PY

uv run python - <<'PY' "$manifest_path" "$events_path"
import json, sys
manifest_path, events_path = sys.argv[1], sys.argv[2]
with open(manifest_path) as f:
    manifest = json.load(f)
manifest["schema_version"] = 3
manifest["event_schema_version"] = 0
with open(manifest_path, "w") as f:
    json.dump(manifest, f)
    f.write("\n")

legacy_rows = []
with open(events_path) as f:
    for line in f:
        if not line.strip():
            continue
        row = json.loads(line)
        legacy_rows.append({"seq": row["seq"], "event": row["event"]})
with open(events_path, "w") as f:
    for row in legacy_rows:
        f.write(json.dumps(row))
        f.write("\n")
PY

"$tool" inspect \
  --manifest "$manifest_path" \
  --events "$events_path" \
  >"$inspect_json"

uv run python - <<'PY' "$inspect_json" "$manifest_path" "$events_path"
import json, sys
inspect_path, manifest_path, events_path = sys.argv[1], sys.argv[2], sys.argv[3]
data = json.load(open(inspect_path))
assert data["command"] == "inspect"
assert data["status"] == "migrated_replay"
report = data["migration_report"]
assert report["manifest_schema"] == {"from": 3, "to": 5}
assert report["event_schema"] == {"from": 0, "to": 1}
assert report["plan_file_schema"] is None
assert report["rewrote_manifest"] is False
assert report["rewrote_events"] is False
assert report["rewrote_plan_file"] is False
manifest = json.load(open(manifest_path))
assert manifest["schema_version"] == 3
assert manifest["event_schema_version"] == 0
with open(events_path) as f:
    first = json.loads(next(line for line in f if line.strip()))
assert "schema_version" not in first
PY

"$tool" upgrade \
  --manifest "$manifest_path" \
  --events "$events_path" \
  >"$upgrade_json"

uv run python - <<'PY' "$upgrade_json" "$manifest_path" "$events_path"
import json, sys
upgrade_path, manifest_path, events_path = sys.argv[1], sys.argv[2], sys.argv[3]
data = json.load(open(upgrade_path))
assert data["command"] == "upgrade"
assert data["status"] == "migrated_replay"
report = data["migration_report"]
assert report["manifest_schema"] == {"from": 3, "to": 5}
assert report["event_schema"] == {"from": 0, "to": 1}
assert report["plan_file_schema"] is None
assert report["rewrote_manifest"] is True
assert report["rewrote_events"] is True
assert report["rewrote_plan_file"] is False
manifest = json.load(open(manifest_path))
assert manifest["schema_version"] == 5
assert manifest["event_schema_version"] == 1
with open(events_path) as f:
    first = json.loads(next(line for line in f if line.strip()))
assert first["schema_version"] == 1
PY

"$tool" inspect \
  --manifest "$manifest_path" \
  --events "$events_path" \
  >"$final_json"

uv run python - <<'PY' "$final_json"
import json, sys
data = json.load(open(sys.argv[1]))
assert data["command"] == "inspect"
assert data["status"] == "exact_replay"
assert data["migration_report"] is None
PY

"$tool" seed-plan-backed \
  --manifest "$plan_manifest" \
  --events "$plan_events" \
  >"$plan_seed_json"

uv run python - <<'PY' "$plan_seed_json"
import json, sys
data = json.load(open(sys.argv[1]))
assert data["command"] == "seed_plan_backed"
assert data["status"] == "exact_replay"
assert data["scenario_id"] is None
assert data["migration_report"] is None
PY

uv run python - <<'PY' "$plan_manifest"
import json, sys
path = sys.argv[1]
manifest = json.load(open(path))
manifest["schema_version"] = 4
with open(path, "w") as f:
    json.dump(manifest, f)
    f.write("\n")
PY

"$tool" inspect \
  --manifest "$plan_manifest" \
  --events "$plan_events" \
  >"$plan_inspect_json"

uv run python - <<'PY' "$plan_inspect_json" "$plan_manifest"
import json, sys
inspect_path, manifest_path = sys.argv[1], sys.argv[2]
data = json.load(open(inspect_path))
assert data["command"] == "inspect"
assert data["status"] == "migrated_replay"
report = data["migration_report"]
assert report["manifest_schema"] == {"from": 4, "to": 5}
assert report["event_schema"] is None
assert report["plan_file_schema"] is None
assert report["rewrote_manifest"] is False
assert report["rewrote_events"] is False
assert report["rewrote_plan_file"] is False
manifest = json.load(open(manifest_path))
assert manifest["schema_version"] == 4
PY

"$tool" upgrade \
  --manifest "$plan_manifest" \
  --events "$plan_events" \
  >"$plan_upgrade_json"

uv run python - <<'PY' "$plan_upgrade_json" "$plan_manifest"
import json, sys
upgrade_path, manifest_path = sys.argv[1], sys.argv[2]
data = json.load(open(upgrade_path))
assert data["command"] == "upgrade"
assert data["status"] == "migrated_replay"
report = data["migration_report"]
assert report["manifest_schema"] == {"from": 4, "to": 5}
assert report["event_schema"] is None
assert report["plan_file_schema"] is None
assert report["rewrote_manifest"] is True
assert report["rewrote_events"] is False
assert report["rewrote_plan_file"] is False
manifest = json.load(open(manifest_path))
assert manifest["schema_version"] == 5
assert manifest["artifact_schema_version"] == 1
PY

"$tool" inspect \
  --manifest "$plan_manifest" \
  --events "$plan_events" \
  >"$plan_final_json"

uv run python - <<'PY' "$plan_final_json"
import json, sys
data = json.load(open(sys.argv[1]))
assert data["command"] == "inspect"
assert data["status"] == "exact_replay"
assert data["migration_report"] is None
PY

"$tool" seed \
  --manifest "$nested_manifest" \
  --events "$nested_events" \
  --scenario direct_return \
  >"$nested_seed_json"

uv run python - <<'PY' "$nested_seed_json" "$nested_manifest" "$nested_events"
import json, os, sys
seed_path, manifest_path, events_path = sys.argv[1], sys.argv[2], sys.argv[3]
data = json.load(open(seed_path))
assert data["command"] == "seed"
assert data["status"] == "exact_replay"
assert os.path.exists(manifest_path)
assert os.path.exists(events_path)
PY
