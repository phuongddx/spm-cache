#!/usr/bin/env bash
# Collect spm-cache diagnostics for bug reports.
# Usage: collect_diagnostics.sh [project_dir]
# Output: diagnostic info to stdout

set -euo pipefail
PROJECT_DIR="${1:-.}"
cd "$PROJECT_DIR"

echo "## Environment"
echo ""
echo "- **OS**: $(uname -s) $(uname -r)"
echo "- **Ruby**: $(ruby --version 2>/dev/null || echo 'not found')"
echo "- **Swift**: $(swift --version 2>&1 | head -1 || echo 'not found')"
echo "- **Xcode**: $(xcodebuild -version 2>/dev/null | tr '\n' ' ' || echo 'not found')"

# Determine spm-cache version
SPM_CACHE_VER="not installed"
if command -v spm-cache >/dev/null 2>&1; then
  SPM_CACHE_VER=$(gem list spm-cache 2>/dev/null | grep spm-cache | head -1 || echo "installed (version unknown)")
fi
echo "- **spm-cache**: $SPM_CACHE_VER"
echo ""

echo "## Project"
echo ""
if ls *.xcodeproj >/dev/null 2>&1; then
  echo "- **Xcode project**: $(ls -d *.xcodeproj | head -1)"
else
  echo "- **Xcode project**: none found in $(pwd)"
fi

if [ -f "spm-cache.yml" ]; then
  echo "- **spm-cache.yml**:"
  echo ""
  echo '```yaml'
  cat spm-cache.yml
  echo '```'
else
  echo "- **spm-cache.yml**: not found"
fi

if [ -f "spm-cache.lock" ]; then
  echo "- **spm-cache.lock**: exists"
else
  echo "- **spm-cache.lock**: not found"
fi
echo ""

echo "## Cache State"
echo ""
echo '```'
spm-cache cache list 2>&1 || echo "(cache list failed or no cache)"
echo '```'
echo ""

echo "## Sandbox"
echo ""
if [ -d "spm-cache" ]; then
  echo "- Sandbox exists at \`spm-cache/\`"
  if [ -f "spm-cache/packages/proxy/graph.json" ]; then
    echo "- **graph.json status**:"
    echo ""
    echo '```'
    python3 -c "
import json
try:
    g = json.load(open('spm-cache/packages/proxy/graph.json'))
    if isinstance(g, dict):
        for k, v in g.items():
            if isinstance(v, dict) and 'status' in v:
                print(f\"  {k}: {v['status']}\")
            elif isinstance(v, list):
                print(f\"  {k}: {len(v)} items\")
            else:
                print(f\"  {k}: {v}\")
    elif isinstance(g, list):
        print(f'  graph: {len(g)} entries')
except Exception as e:
    print(f'  (parse error: {e})')
" 2>/dev/null || echo "  (could not parse graph.json)"
    echo '```'
  fi
else
  echo "- No sandbox found (spm-cache/ directory does not exist)"
fi
