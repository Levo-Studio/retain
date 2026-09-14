#!/bin/bash
# Installs the repository's git hooks.
#
# Hooks live in .git/hooks, which git does not track, so a clone starts without
# them. Run this once after cloning.
set -euo pipefail
cd "$(dirname "$0")/.."
cp .githooks/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
echo "installed: pre-commit (refuses a signing identity in project.pbxproj)"
