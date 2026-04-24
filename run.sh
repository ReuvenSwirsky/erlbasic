#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"

find_rebar3() {
    local candidate

    for candidate in \
        "${REBAR3:-}" \
        "$script_dir/rebar3" \
        "$HOME/rebar3"
    do
        if [[ -n "$candidate" && -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    if command -v rebar3 >/dev/null 2>&1; then
        command -v rebar3
        return 0
    fi

    echo "rebar3 not found. Set REBAR3 or install rebar3 in PATH, $script_dir/rebar3, or $HOME/rebar3." >&2
    return 1
}

rebar3_cmd="$(find_rebar3)"

config_file="sys.config"

if [[ ! -f "$config_file" ]]; then
    printf 'No sys.config found, running with defaults\n' >&2
    echo "Starting erlbasic..."
    "$rebar3_cmd" shell
else
    echo "Loading configuration from $config_file"
    echo "Starting erlbasic..."
    "$rebar3_cmd" shell --config "$config_file"
fi