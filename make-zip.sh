#!/bin/sh
# USB/직접 전달용 zip 생성 (저장소 공개 여부와 무관한 기본 배포 경로). 사용: ./make-zip.sh [출력경로]
set -e
out="${1:-ax-field-kit.zip}"
git archive --format=zip --prefix=ax-field-kit/ -o "$out" HEAD
echo "생성: $out"
