#!/usr/bin/env bash
# Vendors Codec2 into KV4PDigital and generates its golden test vectors
# (ADR-0005, ADR-0027). The pinned upstream commit is the one codec2-android
# (the Android app's FreeDV codec) builds, with its mode switches: only the
# Codec2 1300 mode is compiled in.
# Usage: generate.sh   (run via `make vectors`)
set -euo pipefail

REPOSITORY=https://github.com/drowe67/codec2.git
COMMIT=06d4c11e699b0351765f10398abb4f663a984f36  # Codec2 1.2.0
VERSION=(1 2 0)
DEFINES=(-DCODEC2_MODE_EN_DEFAULT=0 -DCODEC2_MODE_1300_EN=1)
# codec2-android's source list. It links with --gc-sections, which drops the
# code paths of the disabled modes; SwiftPM debug builds do not dead-strip, so
# the sources those paths refer to (newamp1.c, mbest.c and the codebooks below
# after codebook.c) are compiled too. Mode 1300 never runs them.
SOURCES=(codec2.c codec2_fft.c dump.c interp.c kiss_fft.c kiss_fftr.c lpc.c lsp.c nlp.c
  pack.c phase.c postfilter.c quantise.c sine.c newamp1.c mbest.c)
# Generated codebooks as in Codec2's src/CMakeLists.txt: "<file> <symbol> <inputs…>".
CODEBOOKS=(
  "codebook.c lsp_cb lsp1.txt lsp2.txt lsp3.txt lsp4.txt lsp5.txt lsp6.txt lsp7.txt lsp8.txt lsp9.txt lsp10.txt"
  "codebookd.c lsp_cbd dlsp1.txt dlsp2.txt dlsp3.txt dlsp4.txt dlsp5.txt dlsp6.txt dlsp7.txt dlsp8.txt dlsp9.txt dlsp10.txt"
  "codebookjmv.c lsp_cbjmv lspjmv1.txt lspjmv2.txt lspjmv3.txt"
  "codebookge.c ge_cb gecb.txt"
  "codebooknewamp1.c newamp1vq_cb train_120_1.txt train_120_2.txt"
  "codebooknewamp1_energy.c newamp1_energy_cb newamp1_energy_q.txt"
)

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
build="$here/build"
upstream="$build/codec2"
generated="$build/generated"
package="$root/apple-src/Packages/KV4PDigital"
target="$package/Sources/CCodec2"
vectors="$package/Tests/KV4PDigitalTests/Vectors"

if [[ ! -d "$upstream/.git" ]]; then
  git clone --quiet "$REPOSITORY" "$upstream"
fi
git -C "$upstream" checkout --quiet "$COMMIT" 2>/dev/null \
  || { git -C "$upstream" fetch --quiet origin; git -C "$upstream" checkout --quiet "$COMMIT"; }
src="$upstream/src"

# Generated sources, as Codec2's CMake build makes them. The codebook generator
# runs inside codebook/ so the file names it embeds are relative.
rm -rf "$generated"
mkdir -p "$generated/codec2"
cc "$src/generate_codebook.c" -o "$build/generate_codebook" -lm
codebooks=()
for entry in "${CODEBOOKS[@]}"; do
  read -r file symbol inputs <<<"$entry"
  # shellcheck disable=SC2086 # the inputs are separate arguments
  (cd "$src/codebook" && "$build/generate_codebook" "$symbol" $inputs) >"$generated/$file"
  codebooks+=("$generated/$file")
done
sed -e "s/@CODEC2_VERSION_MAJOR@/${VERSION[0]}/" \
  -e "s/@CODEC2_VERSION_MINOR@/${VERSION[1]}/" \
  -e "s/#cmakedefine CODEC2_VERSION_PATCH @CODEC2_VERSION_PATCH@/#define CODEC2_VERSION_PATCH ${VERSION[2]}/" \
  -e "s/@CODEC2_VERSION@/${VERSION[0]}.${VERSION[1]}.${VERSION[2]}/" \
  "$upstream/cmake/version.h.in" >"$generated/codec2/version.h"

# Vendored copy: the sources, the headers they include, the generated files.
headers=$(cd "$src" && cc -MM "${DEFINES[@]}" -I. -I"$generated" "${SOURCES[@]}" \
  | tr ' \\' '\n\n' | grep -E '^[^/].*\.h$' | sort -u)
rm -rf "$target"
mkdir -p "$target/include/codec2"
for file in "${SOURCES[@]}" $headers; do
  [[ "$file" == codec2.h ]] && continue
  cp "$src/$file" "$target/$file"
done
cp "${codebooks[@]}" "$target/"
cp "$src/codec2.h" "$target/include/codec2.h"
cp "$generated/codec2/version.h" "$target/include/codec2/version.h"
cp "$upstream/COPYING" "$package/COPYING-codec2"

# Vectors from the pristine checkout, optimised like codec2-android's release build.
sources=()
for file in "${SOURCES[@]}"; do sources+=("$src/$file"); done
cc -O2 "${DEFINES[@]}" -I"$src" -I"$generated" -I"$generated/codec2" \
  "$here/reference.c" "${sources[@]}" "${codebooks[@]}" -o "$build/reference" -lm
mkdir -p "$vectors"
"$build/reference" >"$vectors/codec2.json"
