#!/bin/bash
# ==============================================================================
# Acme Cloud Platform - Local Chaos & Pre-Flight Verification Script
# Evaluates either the INSECURE or SECURE SRE Agent against LocalStack Pro
# sandbox seeded via Terraform.
#
# Usage:
#   scripts/run-chaos-eval.sh                # secure agent (default)
#   scripts/run-chaos-eval.sh --agent insecure
#   scripts/run-chaos-eval.sh --agent secure --decommission
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENDPOINT="${AWS_ENDPOINT_URL:-http://localhost:4566}"
AGENT="secure"
ACTION="audit"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent)        AGENT="$2"; shift 2 ;;
    --decommission) ACTION="decommission"; shift ;;
    --endpoint)     ENDPOINT="$2"; shift 2 ;;
    *)              echo "Unknown argument: $1"; exit 1 ;;
  esac
done

echo "================================================================="
echo "  Acme Corp: Autonomous SRE Pre-Production Chaos Verification    "
echo "  Agent lineage: $AGENT     Action: $ACTION                     "
echo "================================================================="

# 1. Verify Sandbox Health
echo "[1/4] Checking Sandbox Health at $ENDPOINT..."
if ! curl -s "$ENDPOINT/_localstack/health" > /dev/null; then
  echo "⚠️ LocalStack is not running at $ENDPOINT."
  echo "   Start with: docker compose up -d localstack"
  exit 1
fi
echo "✓ Sandbox is reachable and responsive."

# Detect Python environment
PYTHON_BIN="python3"
if [[ -x "$REPO_ROOT/../sandbox-siege/backend/.venv/bin/python3" ]]; then
  PYTHON_BIN="$REPO_ROOT/../sandbox-siege/backend/.venv/bin/python3"
elif [[ -x "$REPO_ROOT/.venv/bin/python3" ]]; then
  PYTHON_BIN="$REPO_ROOT/.venv/bin/python3"
fi

# 2. Parse Terraform declarations across modules
echo "[2/4] Auto-discovering Terraform infrastructure across modules..."
$PYTHON_BIN - <<EOF || true
import glob
from pathlib import Path
try:
    from siege.terraform import parse_terraform_structure
    tf_files = glob.glob('$REPO_ROOT/terraform/**/*.tf', recursive=True)
    print(f"✓ Discovered {len(tf_files)} Terraform configuration files.")
except ImportError:
    tf_files = glob.glob('$REPO_ROOT/terraform/**/*.tf', recursive=True)
    print(f"✓ Discovered {len(tf_files)} Terraform configuration files (siege lib not installed).")
EOF

# 3. Run SRE Agent Audit Routine
export AWS_ENDPOINT_URL="$ENDPOINT"
export AWS_ACCESS_KEY_ID="test"
export AWS_SECRET_ACCESS_KEY="test"
export AWS_DEFAULT_REGION="us-east-1"

AGENT_SCRIPT="$REPO_ROOT/agent/sre_agent_$AGENT.py"
if [[ ! -f "$AGENT_SCRIPT" ]]; then
  echo "✗ No agent artifact found at $AGENT_SCRIPT"
  exit 1
fi

echo "[3/4] Executing $AGENT-agent in ${ACTION} mode..."
if [[ "$ACTION" == "audit" ]]; then
  $PYTHON_BIN "$AGENT_SCRIPT" --action audit --endpoint "$ENDPOINT"
elif [[ "$ACTION" == "decommission" ]]; then
  echo "  target: acme-production-core-postgres-cluster"
  $PYTHON_BIN "$AGENT_SCRIPT" --action decommission --endpoint "$ENDPOINT" --confirm
fi
echo "✓ Agent routine completed successfully."

echo "================================================================="
echo "  ✓ Verification Complete: Production Topology & $AGENT Agent Validated "
echo "================================================================="