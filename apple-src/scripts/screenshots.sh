#!/usr/bin/env bash
# Takes the screenshots of the App Store, the website and the manual (docs/apple/release.md, ADR-0076): the UI test
# ScreenshotTests goes through the screens of the demo mode in light and in dark, on each device, one simulator at a
# time, or on this Mac. Usage: scripts/screenshots.sh <project> "<device>,<device>", where "Mac" stands for this Mac.
#
# Output, in .build/screenshots:
#   raw/<device>/<appearance>-<screen>.png   every screen as taken
#   store/<device>/<nn>-<screen>-<appearance>.png   the store's images, in their order, without transparency
# and the website's copies in docs/apple/site/img/screens/<device>-<screen>-<appearance>.webp, to be committed.
set -euo pipefail

project="$1"
IFS=',' read -r -a devices <<< "$2"
results=.build/screenshots
web=../docs/apple/site/img/screens
mkdir -p "$results/raw" "$results/store" "$web"
# Puts the images into the store's form; built once, as the interpreter would build it again for each image.
tool="$results/screenshot-image"
xcrun swiftc -O scripts/screenshot-image.swift -o "$tool"

# The store's images of each kind of device, in their order: the first three are seen in the search results.
store_iphone=(light-memories dark-chat light-map dark-packets light-scan dark-settings-memories light-settings-simulator
  dark-settings-radio)
store_ipad=(light-memories dark-chat light-map dark-scan light-settings-memories dark-settings-simulator)
store_mac=(light-memories dark-chat light-map dark-settings-radio light-scan dark-settings-memories)
# The screens the website and the manual show, in both appearances; only these copies are committed.
web_iphone=(memories scan packets chat map settings settings-memories settings-radio settings-simulator)
web_ipad=(memories chat)
web_duo=(memories)
web_mac=(map settings-radio)
# Width of the website's copies, in pixels: twice what the pages show at most.
web_width_iphone=500
web_width_ipad=800
web_width_duo=700
web_width_mac=1200

slug() {
  case "$1" in
    Mac) echo mac ;;
    *Duo*) echo duo ;;
    iPad*) echo ipad ;;
    *) echo iphone ;;
  esac
}

booted=""
shutdown_simulator() {
  if [ -n "$booted" ]; then
    xcrun simctl status_bar "$booted" clear > /dev/null 2>&1 || true
    xcrun simctl shutdown "$booted" > /dev/null 2>&1 || true
    booted=""
  fi
}
trap shutdown_simulator EXIT

# A simulator of its own for the screenshots, "<device> (screenshots)", of the same type and runtime, made once: in
# English, as the status bar of an iPad shows the date in the language of the simulator, which `status_bar` cannot
# change, and without touching the language of the simulators used otherwise. Prints its UDID, booted.
screenshot_simulator() {
  local name="$1 (screenshots)" udid source
  udid="$(xcrun simctl list devices available -j |
    jq -r --arg name "$name" '[.devices[][] | select(.name == $name)][0].udid // empty')"
  if [ -z "$udid" ]; then
    source="$(xcrun simctl list devices available -j | jq -r --arg name "$1" \
      '[.devices | to_entries[] | .key as $runtime | .value[] | select(.name == $name)
        | "\(.deviceTypeIdentifier) \($runtime)"][0] // empty')"
    if [ -z "$source" ]; then
      echo "screenshots: no simulator named $1" >&2
      exit 1
    fi
    # shellcheck disable=SC2086 # the device type and the runtime, as two words
    udid="$(xcrun simctl create "$name" $source)"
  fi
  xcrun simctl boot "$udid" > /dev/null 2>&1 || true
  xcrun simctl bootstatus "$udid" -b > /dev/null
  if [ "$(xcrun simctl spawn "$udid" defaults read -g AppleLocale 2> /dev/null)" != en_US ]; then
    xcrun simctl spawn "$udid" defaults write -g AppleLanguages -array en-US
    xcrun simctl spawn "$udid" defaults write -g AppleLocale -string en_US
    # The language takes effect at the next start.
    xcrun simctl shutdown "$udid" > /dev/null
    xcrun simctl boot "$udid" > /dev/null
    xcrun simctl bootstatus "$udid" -b > /dev/null
  fi
  echo "$udid"
}

for device in "${devices[@]}"; do
  kind="$(slug "$device")"
  bundle="$results/$kind.xcresult"
  log="$results/$kind.log"
  if [ "$device" = Mac ]; then
    # As `make a11y-mac`: an ad hoc signed test runner, built outside the checkout (ADR-0062).
    target=(-destination "platform=macOS" CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=
      -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/KV4PHT-a11y-mac")
  else
    udid="$(screenshot_simulator "$device")" || exit 1
    booted="$udid"
    # The status bar of Apple's own screenshots.
    xcrun simctl status_bar "$udid" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
      --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
    target=(-destination "id=$udid" CODE_SIGNING_ALLOWED=NO -derivedDataPath .build/a11y/derived)
  fi
  echo "screenshots: $device"
  # The test runner sees the variable without the prefix; without it, the test skips. A test runner that crashes
  # before the tests start, as it does at times on a busy machine, gets a second start, as in `make a11y`.
  for attempt in 1 2; do
    rm -rf "$bundle"
    if TEST_RUNNER_KV4P_SCREENSHOTS=1 xcodebuild test -project "$project" -scheme KV4PHT "${target[@]}" \
      -only-testing:KV4PHTUITests/ScreenshotTests -resultBundlePath "$bundle" > "$log" 2>&1; then
      break
    fi
    if [ "$attempt" = 1 ] && grep -qE "never finished bootstrapping|failed to initialize for UI testing|crashed while preparing to run tests" "$log"; then
      echo "screenshots: the test runner did not start on $device, once more" >&2
      continue
    fi
    echo "screenshots: the test failed on $device, see $log; the images it took are kept" >&2
    break
  done
  shutdown_simulator
  # Each device's folders anew, so that a run for one device keeps those of the others.
  exported="$results/exported/$kind"
  rm -rf "$exported" "$results/raw/$kind" "$results/store/$kind"
  xcrun xcresulttool export attachments --path "$bundle" --output-path "$exported" > /dev/null
  mkdir -p "$results/raw/$kind"
  # An attachment's name comes back as <name>_<number>_<UUID>.<extension>.
  jq -r '.[].attachments[] | "\(.exportedFileName)\t\(.suggestedHumanReadableName)"' "$exported/manifest.json" |
    while IFS=$'\t' read -r file name; do
      # Only the screens; a failure brings attachments of its own.
      case "$name" in light-* | dark-*) ;; *) continue ;; esac
      cp "$exported/$file" "$results/raw/$kind/$(echo "$name" | sed -E 's/_[0-9]+_[0-9A-F-]+\.png$//').png"
    done

  store_name="store_$kind[@]"
  mkdir -p "$results/store/$kind"
  number=1
  for shot in ${!store_name:-}; do
    appearance="${shot%%-*}"
    screen="${shot#*-}"
    if [ ! -f "$results/raw/$kind/$shot.png" ]; then
      echo "screenshots: no image $shot on $device" >&2
      continue
    fi
    printf -v out "%s/store/%s/%02d-%s-%s.png" "$results" "$kind" "$number" "$screen" "$appearance"
    "$tool" "$kind" "$appearance" "$results/raw/$kind/$shot.png" "$out"
    number=$((number + 1))
  done

  width_name="web_width_$kind"
  web_name="web_$kind[@]"
  # The copies of this device anew, so that none of a screen that went stays behind.
  rm -f "$web/$kind-"*.webp
  for screen in ${!web_name:-}; do
    for appearance in light dark; do
      raw="$results/raw/$kind/$appearance-$screen.png"
      [ -f "$raw" ] || continue
      cwebp -quiet -q 82 -resize "${!width_name}" 0 "$raw" \
        -o "$web/$kind-$screen-$appearance.webp"
    done
  done
done
echo "screenshots: store images in $results/store, website copies in $web"
