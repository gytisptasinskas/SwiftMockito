#!/bin/bash
# Regenerates the golden mocks with the CLI and fails if they differ from the checked-in files.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
fixtures="$root/Tests/SwiftMockitoTests/Fixtures"
printf '@GenerateMock(Client.self, Catalog.self, Screen.self, Feed.self, Edge.self, Store.self, Shapes.self, Escapes.self)\nenum Mocks {}\n' > "$out/Mocks.swift"
swift run --package-path "$root" SwiftMockitoGenerator generate \
  --test-module SwiftMockitoTests --output "$out/generated" --marked "$out/Mocks.swift" \
  --source-dir "SwiftMockitoTests=$fixtures"
status=0
for name in MockClient MockCatalog MockScreen MockFeed MockEdge MockStore MockShapes MockEscapes; do
  if [ ! -f "$out/generated/$name.swift" ]; then
    echo "missing generated $name.swift"
    status=1
  else
    diff -u "$fixtures/$name.swift" "$out/generated/$name.swift" || status=1
  fi
done
if [ "$status" -ne 0 ]; then
  echo "checked-in mocks have drifted"
  exit 1
fi
echo "checked-in mocks are up to date"
