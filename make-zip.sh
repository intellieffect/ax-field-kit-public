#!/bin/sh
# USB/직접 전달용 zip 생성 (GitHub 다운로드가 막힐 때). 사용: ./make-zip.sh [출력경로]
set -e
out="${1:-ax-field-kit.zip}"
git archive --format=zip --prefix=ax-field-kit/ -o "$out" HEAD
echo "생성: $out"
