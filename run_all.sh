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

echo "========================================"
echo "BUILD"
echo "========================================"
"$rebar3_cmd" compile
echo

echo "========================================"
echo "EUNIT TESTS"
echo "========================================"
"$rebar3_cmd" eunit
echo

echo "========================================"
echo "SMOKE TESTS"
echo "========================================"
(
    cd smoke_tests
    escript smoke_runner.escript .
)
echo

echo "========================================"
echo "PERF TESTS (pass/fail)"
echo "========================================"
escript perf_tests/perf_runner.escript "$script_dir"
echo

echo "========================================"
echo "WS GRAPHICS BENCHMARK"
echo "========================================"
escript perf_tests/ws_graphics_benchmark.escript "$script_dir"
echo

echo "========================================"
echo "TEXTLIFE BENCHMARK (100 generations)"
echo "========================================"
escript perf_tests/textlife_100gen_benchmark.escript "$script_dir"
echo

echo "========================================"
echo "ALL TESTS PASSED"
echo "========================================"