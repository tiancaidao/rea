#!/bin/bash
# Build the iOS release IPA and publish it to App Store Connect with fastlane.
#
# Usage: scripts/publish_ios.sh [beta|build|upload|listing]
#   beta     build a signed IPA and upload it to TestFlight (default)
#   build    only build the signed IPA into build/ios/ipa/
#   upload   upload an existing IPA (IPA=path, default build/ios/ipa/*.ipa)
#   listing  upload the store text (fastlane/metadata) and screenshots
#            (store_listing/ios/screenshots); never submits for review
#
# Credentials come from fastlane/.env (copy fastlane/.env.example) or the
# environment. Pass CHANGELOG="..." or BUILD_NUMBER=N to override defaults.

set -euo pipefail

LANE="${1:-beta}"
case "$LANE" in
  beta|build|upload|listing) ;;
  -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
  *) echo "Unknown lane '$LANE'. Use beta, build, upload or listing."; exit 1 ;;
esac

cd "$(dirname "$0")/.."

# fastlane and xcpretty crash on Xcode output without a UTF-8 locale.
export LANG="${LANG:-en_US.UTF-8}" LC_ALL="${LC_ALL:-en_US.UTF-8}"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "ERROR: iOS builds need macOS with Xcode."
  exit 1
fi

for tool in flutter bundle; do
  if ! command -v "$tool" >/dev/null; then
    echo "ERROR: '$tool' not found. Install it first (bundle: 'gem install bundler')."
    exit 1
  fi
done

bundle config set --local path vendor/bundle >/dev/null
bundle check >/dev/null 2>&1 || bundle install

exec bundle exec fastlane ios "$LANE"
