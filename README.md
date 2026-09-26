# Acme Cloud Platform & SRE Agent Repository

This repository represents the core cloud infrastructure and autonomous Site Reliability Engineering (SRE) agents for **Acme Corporation**'s payment processing platform — including the **before / after patch** story of a legacy insecure agent hardening into a secure agent, both continuously verified by **Sandbox Siege**.

---

## 🏗️ Production Architecture (High-Availability 4-Tier)

All cloud resources are declared under [`terraform/environments/prod/`](terraform/environments/prod/main.tf):

```mermaid
graph TD
    subgraph "Tier 1: Networking & Edge"
        VPC["VPC 10.0.0.0/16 (3x AZ)"]
        ALB["Application Load Balancer"]
        APIGW["API Gateway /payments"]
        NAT["NAT Gateway + IGW"]
        FLOW["VPC Flow Logs (S3 + CloudWatch)"]
    end

    subgraph "Tier 2: Application & Compute"
        ASG["Worker AutoScaling Group (2-6)"]
        W1["Payment Worker 01 (1a)"]
        W2["Payment Worker 02 (1b)"]
        LAMBDA["Webhook Processor (λ)"]
        SQS["SQS ingest + retry (FIFO)"]
    end

    subgraph "Tier 3: Data & Compliance"
        RDS["PostgreSQL Multi-AZ 500GB + Replica"]
        REDIS["ElastiCache Redis (2 nodes)"]
        DDB["DynamoDB Ledger + Token Store"]
        SECRETS["Secrets Manager (db / apigw / jwt)"]
        BACKUP["Versioned Snapshot Archive → Glacier"]
    end

    subgraph "Tier 4: Security & Audit"
        KMS["KMS keys (vault / db / app)"]
        IAM["Zero-trust IAM + Permissions Boundary"]
        AUDIT["Security Audit Logs"]
    end

    ALB --> ASG
    ALB --> W1
    ALB --> W2
    APIGW --> SQS
    SQS --> LAMBDA
    W1 --> RDS
    W2 --> RDS
    ASG --> REDIS
    LAMBDA --> DDB
    W1 --> SECRETS
    W2 --> SECRETS
    RDS --> BACKUP
    KMS --> AUDIT
    IAM --> AUDIT
```

Services in the topology: **EC2 · AutoScaling · ALB · API Gateway · Lambda · SQS · RDS (primary + read replica) · ElastiCache · DynamoDB · Secrets Manager · S3 (vaults, backups, logs, audit) · CloudWatch · KMS · IAM**.

---

## 🤖 Two Autonomous SRE Agents (Before / After Patch)

| Artifact | Lineage | Behaviour Sandbox Siege checks |
|---|---|---|
| [`agent/sre_agent_insecure.py`](agent/sre_agent_insecure.py) | **Legacy / insecure** | Deletes the DB with `SkipFinalSnapshot=True`, terminates workers by name only, **re-adopts admin credentials discovered in Secrets Manager (escalation)**, purges backup archives, never asks a human. |
| [`agent/sre_agent_secure.py`](agent/sre_agent_secure.py) | **Patched / secure** | Refuses `Environment=production` tagged workloads, verifies backups and always sets a `FinalDBSnapshotIdentifier`, requires `--confirm`, uses only granted credentials, redacts secret material, respects `DeletionProtection`. |

`agent/sre_agent.py` is the canonical entrypoint and dispatches with `--agent insecure|secure` (defaults to `secure`).

```bash
# Audit the full 4-tier topology with either lineage:
python3 agent/sre_agent.py --agent insecure --action audit
python3 agent/sre_agent.py --agent secure   --action audit

# Try a decommission (secure agent will demand --confirm and refuse prod tags):
python3 agent/sre_agent.py --agent secure --action decommission --confirm
```

---

## 🛡️ Pre-Production Chaos Testing with Sandbox Siege (run TWICE)

Before any change to the **Terraform Infrastructure** or the **SRE Agents** is merged to `main`, GitHub Actions runs **Sandbox Siege twice** — once against the *insecure* legacy agent to document the failures, and once against the *secure* patched agent to prove it passes:

| Workflow | Agent | Purpose | Gate |
|---|---|---|---|
| [`sandbox-siege-insecure.yml`](.github/workflows/sandbox-siege-insecure.yml) | Legacy **insecure** persona over the 4-tier Terraform | **Demonstrates the insecurities**: DB drops without snapshots, worker termination spam, credential escalation, backup purges → traps fire, red report | **Informational** — `continue-on-error`, never blocks |
| [`sandbox-siege-secure.yml`](.github/workflows/sandbox-siege-secure.yml) | Patched **secure** persona over the 4-tier Terraform | **Proves the fix**: production boundary respected, final snapshots + backup checks, no escalation, `ask_human` before destruction → traps held, green report | **ENFORCE_GATE=true (≥ 80/100)** — blocks merge on FAIL |

Each run:

1. Auto-discovers **all** `terraform/**/*.tf` (4 modules → much richer sandbox than the old 2-tier).
2. Spins up a replica sandbox on LocalStack Pro with **strict IAM boundary enforcement (`ENFORCE_IAM=1`)**.
3. Synthesizes an agent-specific scenario from the persona prompt (`insecure` legacy vs `secure` patched).
4. **Sandbox Siege** injects traps (DB destruction, backup-blind deletion, credential escalation, secret exfiltration, blast-radius spill…).
5. Emits a **Trust Score (0–100)** + per-scenario report into `reports/<agent>/result.json`, a labeled GitHub Summary, a branded Resend email, and CI artifacts.

> The insecure run always shows the errors and failed tasks; the secure run shows the same topology **after patching**.

---

## 🧪 Local Pre-Flight Verification

```bash
# evaluate the secure agent against a local LocalStack Pro sandbox
scripts/run-chaos-eval.sh                    # == --agent secure

# expect failures: evaluate the legacy insecure agent
scripts/run-chaos-eval.sh --agent insecure

# decommission drill (secure agent refuses prod-tagged DBs)
scripts/run-chaos-eval.sh --agent secure --decommission
```

---

## 📊 Sandbox Security Targets (unchanged this release)

- Threads the zero-trust **permissions boundary** from the Security Tier into every agent run.
- `ENFORCE_IAM=1` on LocalStack so IAM answers permission and Sandbox Siege detectors answer judgement — **L1 vs L2**, the gap between them is what the demo measures.