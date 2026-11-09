#!/usr/bin/env bash
#
# mayhem/build.sh — builds LibreSprite's file loaders for fuzzing, plus the unit tests used by test.sh.
#
# Runs inside the commit image (mayhem/Dockerfile) as `mayhem` in /mayhem, air-gapped and re-runnable:
# cmake 4.x and the two git-submodule sources (flic, simpleini) come from /opt/toolchains/deps.
#   1. build/fuzz   — the whole app library, sanitized ($SANITIZER_FLAGS, DWARF 3), linked into one
#                     libFuzzer binary + one -standalone reproducer per target (/mayhem/fuzz_<t>[-standalone]).
#   2. build/tests  — the same sources with NORMAL flags; the gtest suites and mayhem/dump_image that
#                     mayhem/test.sh runs.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

# The project needs cmake >= 4.1 (the base ships an older one).
export PATH="/opt/toolchains/deps/cmake-4.4.3/bin:$PATH"

# flic and simpleini are submodules (empty directories in a plain checkout); fill them from the pinned copies.
for pair in src/flic:flic-876ef60 third_party/simpleini:simpleini-c94997d; do
  dst="${pair%%:*}"; dep="/opt/toolchains/deps/${pair##*:}/src"
  mkdir -p "$dst"
  cp -a "$dep/." "$dst/"
done

# Libraries the harnesses link against (the app library and what it needs).
APP_TARGETS="libresprite app-lib base-lib cfg-lib css-lib doc-lib filters-lib fixmath-lib flic-lib gfx-lib render-lib she ui-lib undo delta clip httplib"
TEST_TARGETS="base64_tests string_tests path_tests rgb_tests hsv_tests resize_image_tests context_tests ordered_dither_tests"

# -fno-sanitize=function: doc/algo.cpp calls a callback through a differently-typed function pointer on
# purpose (every draw_line/draw_ellipse caller); the rest of UBSan stays on and halting.
# -fsanitize=fuzzer-no-link puts SanCov on the project code; $SANITIZER_FLAGS carries no coverage flag, so
# without it the fuzz binaries build and run but Mayhem records 0 edges.
COV_FLAGS="-fsanitize=fuzzer-no-link"
FUZZ_FLAGS="$SANITIZER_FLAGS $COV_FLAGS -fno-sanitize=function $DEBUG_FLAGS"

# The compiler reaches cmake through the exported CC/CXX rather than -DCMAKE_*_COMPILER: cmake reads them on
# the first configure only, so a re-run whose PATH resolves the name to a different clang (the ccache pre-fill
# shim vs /usr/bin) keeps the cached one instead of discarding the cache and regenerating module-scan rules.

# ---- 1) sanitized build ------------------------------------------------------------------------------
cmake -G Ninja -S . -B build/fuzz -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_SCAN_FOR_MODULES=OFF \
  -DCMAKE_C_FLAGS="$FUZZ_FLAGS" -DCMAKE_CXX_FLAGS="$FUZZ_FLAGS" -DCMAKE_EXE_LINKER_FLAGS="$SANITIZER_FLAGS"
# The build runs its own sanitized code generator (gen); its leaks are not under test.
ASAN_OPTIONS=detect_leaks=0 ninja -C build/fuzz -j"$MAYHEM_JOBS" $APP_TARGETS

# Link recipe shared by the sanitized and the plain build: every format registers itself from a static
# initializer, so the project archives are linked whole. libshe.a also defines main(); a copy with that
# symbol weakened lets the fuzz engine's (or the oracle's own) main win.
link_inputs() {
  local B="$1"
  mkdir -p "$B/harness"
  cp "$B/lib/libshe.a" "$B/harness/libshe-nomain.a"
  llvm-objcopy --weaken-symbol=main "$B/harness/libshe-nomain.a"
  WHOLE="$B/lib/libapp-lib.a $B/lib/libbase-lib.a $B/lib/libcfg-lib.a $B/lib/libclip.a $B/lib/libcss-lib.a \
$B/lib/libdoc-lib.a $B/lib/libfilters-lib.a $B/lib/libfixmath-lib.a $B/lib/libflic-lib.a $B/lib/libgfx-lib.a \
$B/lib/librender-lib.a $B/harness/libshe-nomain.a $B/lib/libui-lib.a $B/lib/libundo.a $B/lib/libdelta.a"
  SYS="$B/lib/libhttplib.a -larchive -ltinyxml2 -ljpeg -lgif -lpng -lz -lwebp -lfreetype -lm -lSM -lICE -lX11 \
-lXext -lXcursor -lXxf86vm -lXi -lssl -lcrypto -lxcb -lpthread $B/lib/libobs.a $B/lib/libmodp_b64.a -ldl \
-lSDL2 -lSDL2_image -lpixman-1 $B/lib/libquickjs.a"
  INC="-DHAVE_CONFIG_H -DNDEBUG -DUSE_SDL2_BACKEND -Ithird_party/qoi -I/usr/include/webp \
-I/usr/include/pixman-1 -I/usr/include/freetype2 -Ithird_party/simpleini -Ithird_party/delta \
-I/usr/include/SDL2 -Isrc -I. -Ithird_party -Ithird_party/observable -I$B/src/base -Ithird_party/modp_b64 \
-I/usr/include/libpng16"
}
link_inputs build/fuzz

mkdir -p build/fuzz/harness
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c mayhem/lsan_off.cc -o build/fuzz/harness/lsan_off.o
$CC  $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o build/fuzz/harness/standalone_main.o

# <target>:<harness source>:<extension fed to the loader>[:<extra -D flag>]
TARGETS="
fuzz_ase:fuzz_file.cpp:ase
fuzz_gif:fuzz_file.cpp:gif
fuzz_bmp:fuzz_file.cpp:bmp
fuzz_tga:fuzz_file.cpp:tga
fuzz_pcx:fuzz_file.cpp:pcx
fuzz_ico:fuzz_file.cpp:ico
fuzz_qoi:fuzz_file.cpp:qoi
fuzz_jpg:fuzz_file.cpp:jpg
fuzz_png:fuzz_file.cpp:png
fuzz_anim:fuzz_file.cpp:anim:-DFUZZ_SIDECAR_PNG
fuzz_fli:fuzz_file.cpp:fli
fuzz_webp:fuzz_file.cpp:webp
fuzz_palette_col:fuzz_palette.cpp:col
fuzz_palette_gpl:fuzz_palette.cpp:gpl
fuzz_palette_pal:fuzz_palette.cpp:pal
"
for entry in $TARGETS; do
  IFS=: read -r name src ext extra <<<"$entry"
  obj="build/fuzz/harness/$name.o"
  $CXX -std=c++20 $SANITIZER_FLAGS $COV_FLAGS $DEBUG_FLAGS -O1 $INC -DFUZZ_EXT="\"$ext\"" ${extra:-} -c "mayhem/$src" -o "$obj"
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "$obj" build/fuzz/harness/lsan_off.o \
    -Wl,--whole-archive $WHOLE -Wl,--no-whole-archive $SYS -o "/mayhem/$name"
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS "$obj" build/fuzz/harness/standalone_main.o build/fuzz/harness/lsan_off.o \
    -Wl,--whole-archive $WHOLE -Wl,--no-whole-archive $SYS -o "/mayhem/$name-standalone"
done

# ---- 2) the test suite, with the project's normal flags -----------------------------------------------
cmake -G Ninja -S . -B build/tests -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_SCAN_FOR_MODULES=OFF \
  -DENABLE_TESTS=ON \
  -DCMAKE_C_FLAGS="$COVERAGE_FLAGS" -DCMAKE_CXX_FLAGS="$COVERAGE_FLAGS" -DCMAKE_EXE_LINKER_FLAGS="$COVERAGE_FLAGS"
ninja -C build/tests -j"$MAYHEM_JOBS" $APP_TARGETS $TEST_TARGETS

link_inputs build/tests
$CXX -std=c++20 -O1 $COVERAGE_FLAGS $INC mayhem/dump_image.cpp \
  -Wl,--whole-archive $WHOLE -Wl,--no-whole-archive $SYS -o build/tests/bin/dump_image
