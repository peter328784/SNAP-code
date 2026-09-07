#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
network_option=${1:-}

case "$network_option" in
  ""|--allow-insecure-local-http) ;;
  *)
    echo "Usage: sh tool/bootstrap_platforms.sh [--allow-insecure-local-http]" >&2
    exit 2
    ;;
esac

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter Stable SDK를 먼저 설치하고 flutter doctor -v를 통과시켜 주세요." >&2
  exit 1
fi

if [ -e "$project_dir/android" ] || [ -e "$project_dir/ios" ]; then
  echo "android/ 또는 ios/가 이미 있습니다. 기존 플랫폼 파일을 덮어쓰지 않습니다." >&2
  exit 1
fi

temp_root=$(mktemp -d "${TMPDIR:-/tmp}/snap-mobile-platforms.XXXXXX")
generated_dir="$temp_root/generated"
cleanup() {
  rm -rf -- "$temp_root"
}
trap cleanup EXIT HUP INT TERM

flutter create \
  --platforms=android,ios \
  --org dev.snap.valet \
  --project-name snap_mobile \
  "$generated_dir"

# flutter create writes machine-local paths into generated files. Do not copy
# those paths from the temporary project into the real checkout.
rm -rf -- "$generated_dir/ios/Flutter/ephemeral"
rm -f -- \
  "$generated_dir/ios/Flutter/Generated.xcconfig" \
  "$generated_dir/ios/Flutter/flutter_export_environment.sh" \
  "$generated_dir/android/local.properties"

cp -R "$generated_dir/android" "$project_dir/android"
cp -R "$generated_dir/ios" "$project_dir/ios"
cp "$generated_dir/.metadata" "$project_dir/.metadata"

(
  cd "$project_dir"
  flutter pub get
  if [ "$network_option" = "--allow-insecure-local-http" ]; then
    dart run tool/configure_local_network.dart --allow-insecure-local-http
  else
    dart run tool/configure_local_network.dart --prepare-platform-network
  fi
)

echo "iOS/Android 플랫폼 러너 생성이 완료됐습니다."
echo "다음 명령: cd \"$project_dir\" && flutter analyze && flutter test"
