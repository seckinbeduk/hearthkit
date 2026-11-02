#!/bin/bash
# Build HearthKit, run its tests and the demo. Keeps full logs in .build/.
#   ./run.sh         everything
#   ./run.sh demo    only the demo
set -uo pipefail
cd "$(dirname "$0")"
mkdir -p .build

if [[ "${1:-all}" != "demo" ]]; then
  echo "── build"
  if ! swift build > .build/build.log 2>&1; then
    grep -E "error:" .build/build.log | sort -u | head -40
    echo "❌ Build failed (full log: .build/build.log)"
    exit 1
  fi
  echo "✅ built"

  echo "── tests"
  swift test > .build/test.log 2>&1
  status=$?
  grep -E "error:|✘|recorded an issue|Test run with" .build/test.log | tail -30
  [[ $status -eq 0 ]] && echo "✅ tests passed" || echo "❌ tests failed (full log: .build/test.log)"
  echo
fi

echo "── demo"
swift run -q hearthkit-demo 2>&1 | tee .build/demo.log
