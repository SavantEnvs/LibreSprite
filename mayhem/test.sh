#!/usr/bin/env bash
#
# mayhem/test.sh — RUN LibreSprite's unit tests and the loader oracle (both built by mayhem/build.sh).
# exit 0 = pass. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

# 1) gtest suites of the base/gfx/doc/render libraries (built with normal flags by build.sh). A binary that
#    prints no "[  PASSED  ]" line (crash, or a neutered program that exits 0 silently) counts as a failure.
passed=0; failed=0
bin=build/tests/bin
for t in base64_tests string_tests path_tests rgb_tests hsv_tests resize_image_tests context_tests ordered_dither_tests; do
  if [ ! -x "$bin/$t" ]; then echo "MISSING test binary $bin/$t (build.sh bug)" >&2; failed=$((failed+1)); continue; fi
  out=$(cd "$bin" && timeout 300 "./$t" 2>&1); rc=$?
  n=$(printf '%s\n' "$out" | sed -n 's/^\[  PASSED  \] \([0-9]*\) test.*/\1/p' | tail -1)
  f=$(printf '%s\n' "$out" | grep -c '^\[  FAILED  \] .*[A-Za-z_]\.[A-Za-z_0-9]* *$' || true)
  if [ -n "$n" ] && [ "$rc" -eq 0 ] && [ "$f" -eq 0 ]; then
    passed=$((passed+n)); echo "ok   $t ($n tests)"
  else
    failed=$((failed+1)); echo "FAIL $t (rc=$rc passed=${n:-none} failed=$f)"; printf '%s\n' "$out" | tail -5
  fi
done

# 2) Loader oracle: decode committed files through LibreSprite's own loaders (app::load_document) and compare
#    what came out (size, frame count, pixel format, two pixel values) to the known-good lines in
#    mayhem/oracle_expected.txt. The lossless formats (png, ase, bmp, tga, qoi, webp, pcx) were all converted
#    from the same 16x16 icon, so they must decode to the same pixels.
dump=build/tests/bin/dump_image
if [ ! -x "$dump" ]; then echo "MISSING $dump (build.sh bug)" >&2; failed=$((failed+1)); else
  while IFS= read -r want; do
    [ -n "$want" ] || continue
    file=${want%% *}
    got=$(timeout 60 "$dump" "$file" 2>/dev/null | grep -E ' [0-9]+x[0-9]+ frames=' | tail -1)
    if [ "$got" = "$want" ]; then passed=$((passed+1)); echo "ok   load $file"
    else failed=$((failed+1)); echo "FAIL load $file"; echo "  want: $want"; echo "  got:  ${got:-<nothing>}"; fi
  done < mayhem/oracle_expected.txt
fi

emit_ctrf "libresprite" "$passed" "$failed" 0
