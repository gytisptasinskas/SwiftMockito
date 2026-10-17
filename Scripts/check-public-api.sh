#!/bin/bash
# Fails if the SwiftMockito module exports matcher-style symbols. The spec forbids them.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
swift package --package-path "$root" dump-symbol-graph --minimum-access-level public >/dev/null
graph=$(find "$root/.build" -path "*symbolgraph*" -name "SwiftMockito.symbols.json" | head -1)
[ -n "$graph" ] || { echo "symbol graph not found"; exit 1; }
names=$(python3 -c 'import json,sys; print("\n".join(s["names"]["title"] for s in json.load(open(sys.argv[1]))["symbols"]))' "$graph")
forbidden='^(any|anyArg|argThat|captor|ArgumentCaptor|wildcard|isA|eq|predicate|matching)(\(|$)'
if echo "$names" | grep -E "$forbidden"; then
  echo "forbidden matcher symbol(s) in public API"
  exit 1
fi
echo "public API has no matcher symbols ($(echo "$names" | wc -l | tr -d ' ') symbols checked)"
