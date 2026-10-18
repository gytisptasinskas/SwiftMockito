#!/bin/bash
# Builds and tests example/app.xcodeproj against this checkout instead of the released package.
#
# The example adds SwiftMockito from GitHub (the Xcode app won't run the plugin from a local `..`
# package). This copies it to a temporary folder and points that copy at the repository root, which
# xcodebuild handles fine, so CI tests the example against the code in the pull request.
#
#   bash Scripts/test-example.sh                    # first available iPhone simulator
#   DESTINATION='platform=iOS Simulator,name=iPhone 17' bash Scripts/test-example.sh
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cp -R "$root/example" "$work/example"
rm -f "$work/example/app.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"

python3 - "$work/example/app.xcodeproj/project.pbxproj" "$root" <<'EOF'
import os, re, sys
path, root = sys.argv[1], sys.argv[2]
text = open(path).read()
pattern = re.compile(
    r'/\* Begin XCRemoteSwiftPackageReference section \*/\n'
    r'(\t\t(\w+) /\* XCRemoteSwiftPackageReference "SwiftMockito" \*/ = \{\n.*?\n\t\t\};\n)'
    r'/\* End XCRemoteSwiftPackageReference section \*/', re.S)
match = pattern.search(text)
if not match:
    sys.exit("test-example.sh: no remote SwiftMockito package reference found in project.pbxproj")
identifier = match.group(2)
relative = os.path.relpath(root, os.path.dirname(os.path.dirname(path)))
local = (
    '/* Begin XCLocalSwiftPackageReference section */\n'
    f'\t\t{identifier} /* XCLocalSwiftPackageReference "SwiftMockito" */ = {{\n'
    '\t\t\tisa = XCLocalSwiftPackageReference;\n'
    f'\t\t\trelativePath = "{relative}";\n'
    '\t\t};\n'
    '/* End XCLocalSwiftPackageReference section */')
open(path, "w").write(text[:match.start()] + local + text[match.end():])
EOF

if [ -z "${DESTINATION:-}" ]; then
  device="$(xcrun simctl list devices available | grep -m1 -oE 'iPhone[^(]*\(([0-9A-F-]{36})\)' | grep -oE '[0-9A-F-]{36}' || true)"
  if [ -z "$device" ]; then
    echo "test-example.sh: no available iPhone simulator" >&2
    exit 1
  fi
  DESTINATION="platform=iOS Simulator,id=$device"
fi

cd "$work/example"
xcodebuild test -project app.xcodeproj -scheme app -destination "$DESTINATION" \
  -skipMacroValidation -skipPackagePluginValidation
