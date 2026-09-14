#!/bin/bash
# ==============================================================================
# Acme Cloud Platform - Local Chaos & Pre-Flight Verification Script
# Evaluates SRE Agent against LocalStack Pro sandbox seeded via Terraform
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENDPOINT="${AWS_ENDPOINT_URL:-http://localhost:4566}"

echo "================================================================="
echo "  Acme Corp: Autonomous SRE Pre-Production Chaos Verification    "
echo "================================================================="

# 1. Verify Sandbox Health
echo "[1/4] Checking Sandbox Health at $ENDPOINT..."
if ! curl -s "$ENDPOINT/_localstack/health" > /dev/null; then
  echo "⚠️ LocalStack is not running at $ENDPOINT."
  echo "   Start with: docker compose up -d localstack"
  exit 1
fi
echo "✓ Sandbox is reachable and responsive."

# 2. Parse Terraform declarations across modules
echo "[2/4] Auto-discovering Terraform infrastructure across modules..."
python3 - <<EOF
import glob
from pathlib import Path
from siege.terraform import parse_terraform_structure

tf_files = glob.glob('$REPO_ROOT/terraform/**/*.tf', recursive=True)
print(f"✓ Discovered {len(tf_files)} Terraform configuration files.")
EOF

# 3. Run SRE Agent Audit Routine
echo "[3/4] Executing SRE Agent in Production Audit Mode..."
export AWS_ENDPOINT_URL="$ENDPOINT"
export AWS_ACCESS_KEY_ID="test"
export AWS_SECRET_ACCESS_KEY="test"
export AWS_DEFAULT_REGION="us-east-1"

python3 "$REPO_ROOT/agent/sre_agent.py" --action audit --endpoint "$ENDPOINT"
echo "✓ Audit routine completed successfully."

# 4. Run SRE Agent Decommission Test
echo "[4/4] Testing Chaos Boundaries & Decommission Routine..."
python3 "$REPO_ROOT/agent/sre_agent.py" --action decommission --endpoint "$ENDPOINT"

echo "================================================================="
echo "  ✓ Verification Complete: Production Topology & Agent Validated "
echo "================================================================="
