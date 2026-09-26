"""
Acme CloudPlatform Autonomous SRE & DevOps Agent — entrypoint.

Dispatch shim between the two agent lineages evaluated by Sandbox Siege:

  * `--agent insecure` → agent.sre_agent_insecure.AcmeInsecureAgent
      The LEGACY artifact; unsafe decommission (skip-final-snapshot DB drops,
      name-only worker termination, credential escalation, backup purges).
      Sandbox Siege run: `.github/workflows/sandbox-siege-insecure.yml`.

  * `--agent secure` (default) → agent.sre_agent_secure.AcmeSecureAgent
      The PATCHED artifact; change-managed decommission (production-tag refusals,
      final-snapshot DB drops after backup verification, --confirm gate,
      no credential escalation). Sandbox Siege run:
      `.github/workflows/sandbox-siege-secure.yml`.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

# Ensure project root is in sys.path
_REPO_ROOT = Path(__file__).resolve().parent.parent
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

try:
    from agent.sre_agent_insecure import AcmeInsecureAgent
    from agent.sre_agent_secure import AcmeSecureAgent
except ImportError:
    from sre_agent_insecure import AcmeInsecureAgent
    from sre_agent_secure import AcmeSecureAgent

AGENTS = {
    "insecure": AcmeInsecureAgent,
    "secure": AcmeSecureAgent,
}


def main():
    parser = argparse.ArgumentParser(description="Acme Autonomous SRE Agent")
    parser.add_argument("--agent", choices=list(AGENTS), default="secure")
    parser.add_argument("--action", choices=["audit", "decommission"], default="audit")
    parser.add_argument("--target", default="acme-production-core-postgres-cluster")
    parser.add_argument("--endpoint", default=None)
    parser.add_argument("--confirm", action="store_true", help="Explicit human approval for decommission (secure agent)")
    args = parser.parse_args()

    agent_cls = AGENTS[args.agent]
    agent = agent_cls(endpoint_url=args.endpoint)

    if args.action == "audit":
        agent.run_health_audit()
    elif args.action == "decommission":
        if hasattr(agent, "confirm") and args.confirm:
            agent.confirm = True
        agent.decommission_legacy_resources(args.target)


if __name__ == "__main__":
    main()