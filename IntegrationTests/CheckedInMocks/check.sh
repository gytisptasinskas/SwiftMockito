#!/bin/bash
# Regenerates the golden mocks with the CLI and fails if they differ from the checked-in files.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
out="$(mktemp -d)"
fixtures="$root/Tests/SwiftMockitoTests/Fixtures"
printf '@GenerateMock(Client.self, Catalog.self, Screen.self, Feed.self, Edge.self, Store.self, Shapes.self)\nenum Mocks {}\n' > "$out/Mocks.swift"
swift run --package-path "$root" SwiftMockitoGenerator generate \
  --test-module SwiftMockitoTests --output "$out/generated" --marked "$out/Mocks.swift" \
  --source-dir "SwiftMockitoTests=$fixtures"
for name in MockClient MockCatalog MockScreen MockFeed MockEdge MockStore MockShapes; do
  diff -u "$fixtures/$name.swift" "$out/generated/$name.swift"
done
echo "checked-in mocks are up to date"
