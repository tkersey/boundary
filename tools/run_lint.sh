#!/bin/sh
set -eu

mode="check"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --fix)
            mode="fix"
            ;;
        --max-warnings)
            shift
            if [ "$#" -eq 0 ]; then
                echo "run_lint.sh: --max-warnings requires a value" >&2
                exit 2
            fi
            ;;
        *)
            echo "run_lint.sh: unsupported argument: $1" >&2
            exit 2
            ;;
    esac
    shift
done

files=$(rg --files -g '*.zig' | rg -v '^(vendor|\.zig-cache|\.zig-global-cache)/')
if [ -z "$files" ]; then
    exit 0
fi

if [ "$mode" = "fix" ]; then
    # Keep the default lint step host-stable by using Zig's formatter directly.
    zig fmt $files
    exit 0
fi

zig fmt --check $files
