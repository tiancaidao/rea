#!/bin/bash
# Run the app's checks before pushing: analyze, format, tests.
#
# Usage: scripts/check.sh [--all-format] [--fix] [--coverage] [-- <flutter test args>]
#
#   --all-format  check the format of every Dart file, not only the changed ones
#   --fix         format the files instead of only checking them
#   --coverage    write coverage/lcov.info and print the total line coverage
#
# The format check covers Dart files changed against the base branch
# (BASE_REF, default origin/main) plus uncommitted and new files, so older
# files are formatted as they are touched. Generated *.g.dart files are skipped.
# Example: scripts/check.sh -- test/scan_engine_test.dart

set -uo pipefail
cd "$(dirname "$0")/.."

ALL_FORMAT=0
FIX=0
COVERAGE=0
TEST_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --all-format) ALL_FORMAT=1 ;;
    --fix) FIX=1 ;;
    --coverage) COVERAGE=1 ;;
    --) shift; TEST_ARGS=("$@"); break ;;
    -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (see --help)"; exit 2 ;;
  esac
  shift
done

BASE_REF="${BASE_REF:-origin/main}"
FAILED=()

step() { printf '\n\033[1m== %s\033[0m\n' "$1"; }

step "Flutter"
flutter --version | head -1

step "Dependencies"
flutter pub get >/dev/null || { echo "flutter pub get failed"; exit 1; }
echo "ok"

step "Analyze (errors and warnings fail; infos are listed only)"
flutter analyze --no-fatal-infos || FAILED+=("analyze")

step "Format"
if [[ $ALL_FORMAT -eq 1 ]]; then
  files=$(git ls-files '*.dart' | grep -v '\.g\.dart$')
else
  base=$(git merge-base HEAD "$BASE_REF" 2>/dev/null) || {
    echo "Can't find $BASE_REF; run 'git fetch origin main' or set BASE_REF. Checking every file."
    base=""
  }
  if [[ -n "$base" ]]; then
    files=$( { git diff --name-only --diff-filter=ACMR "$base" -- '*.dart'
               git ls-files --others --exclude-standard -- '*.dart'; } |
             grep -v '\.g\.dart$' | sort -u)
  else
    files=$(git ls-files '*.dart' | grep -v '\.g\.dart$')
  fi
fi
if [[ -z "$files" ]]; then
  echo "No changed Dart files."
elif [[ $FIX -eq 1 ]]; then
  # shellcheck disable=SC2086
  dart format $files
else
  # shellcheck disable=SC2086
  if ! dart format --output=none --set-exit-if-changed $files; then
    echo "Run scripts/check.sh --fix (or dart format <file>) to format them."
    FAILED+=("format")
  fi
fi

step "Tests"
test_cmd=(flutter test)
[[ $COVERAGE -eq 1 ]] && test_cmd+=(--coverage)
"${test_cmd[@]}" ${TEST_ARGS[@]+"${TEST_ARGS[@]}"} || FAILED+=("tests")

if [[ $COVERAGE -eq 1 && -f coverage/lcov.info ]]; then
  awk -F'[:,]' '/^DA:/ { total++; if ($3 > 0) hit++ }
    END { if (total) printf "Line coverage: %.1f%% (%d of %d lines in files the tests load)\n", 100*hit/total, hit, total }' \
    coverage/lcov.info
fi

echo
if [[ ${#FAILED[@]} -gt 0 ]]; then
  printf '\033[31mFailed: %s\033[0m\n' "${FAILED[*]}"
  exit 1
fi
printf '\033[32mAll checks passed.\033[0m\n'
