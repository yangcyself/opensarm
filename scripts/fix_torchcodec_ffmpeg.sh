#!/usr/bin/env bash
# Make torchcodec (pip wheel, FFmpeg 8 variant) load the FFmpeg shared libraries that
# PyAV bundles in its wheel (site-packages/av.libs), so no system FFmpeg is needed.
#
# torchcodec's libtorchcodec_*8.so declare DT_NEEDED on libavcodec.so.62 etc.; the PyAV
# wheel ships the same libraries under auditwheel's hashed names
# (libavcodec-<hash>.so.62.28.101). We rewrite the needed names and add an RPATH.
# Re-run after `uv sync` / reinstalling torchcodec or av.
#
# Usage: scripts/fix_torchcodec_ffmpeg.sh [python]   (default: .venv/bin/python)
set -euo pipefail
PY=${1:-.venv/bin/python}
SITE=$($PY -c "import sysconfig; print(sysconfig.get_paths()['purelib'])")
AVL=$SITE/av.libs
TC=$SITE/torchcodec
[ -d "$AVL" ] || { echo "no $AVL (is PyAV installed?)"; exit 1; }
[ -d "$TC" ] || { echo "no $TC (is torchcodec installed?)"; exit 1; }
PATCHELF=$(dirname "$PY")/patchelf
[ -x "$PATCHELF" ] || { echo "patchelf missing: run 'uv pip install patchelf' into the venv"; exit 1; }

# FFmpeg major version shipped by PyAV, read from libavcodec's name (libavcodec-xxxx.so.62.x.y)
AVCODEC=$(ls "$AVL"/libavcodec-*.so.* | head -1)
FFMAJOR=$(basename "$AVCODEC" | sed -E 's/.*\.so\.([0-9]+).*/\1/')
case $FFMAJOR in 62) TCV=8;; 61) TCV=7;; 60) TCV=6;; 59) TCV=5;; 58) TCV=4;; *) echo "unknown libavcodec major $FFMAJOR"; exit 1;; esac
echo "PyAV ships libavcodec.so.$FFMAJOR -> patching torchcodec FFmpeg-$TCV libraries"

for lib in "$TC"/libtorchcodec_*"$TCV".so; do
  for needed in $("$PATCHELF" --print-needed "$lib" | grep -E '^lib(av|sw)'); do
    if [[ $needed =~ -[0-9a-f]{8}\.so\. ]]; then continue; fi   # already points at a hashed PyAV lib
    stem=${needed%%.so.*}          # libavcodec
    major=${needed##*.so.}         # 62
    target=$(ls "$AVL"/"$stem"-*.so."$major".* 2>/dev/null | head -1)
    [ -n "$target" ] || { echo "no match for $needed in $AVL"; exit 1; }
    "$PATCHELF" --replace-needed "$needed" "$(basename "$target")" "$lib"
  done
  # DT_RPATH (not RUNPATH): it is also used to resolve the hashed libs' own dependencies
  "$PATCHELF" --force-rpath --set-rpath "$AVL" "$lib"
  echo "patched $(basename "$lib")"
done
$PY -c "import torchcodec; from torchcodec.decoders import VideoDecoder; print('torchcodec', torchcodec.__version__, 'loads OK')"
