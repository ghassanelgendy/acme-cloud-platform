from fastapi import FastAPI, HTTPException
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
import os

app = FastAPI(title="Acme Payments API", version="3.0.0")

# Mount frontend
frontend_dir = os.path.join(os.path.dirname(os.path.dirname(__file__)), "frontend")
if os.path.exists(frontend_dir):
    app.mount("/static", StaticFiles(directory=frontend_dir), name="static")


@app.get("/")
def index():
    index_file = os.path.join(frontend_dir, "index.html")
    if os.path.exists(index_file):
        return FileResponse(index_file)
    return {"status": "ok", "service": "Acme Payments Platform"}


@app.get("/health")
def health():
    return {
        "status": "healthy",
        "service": "acme-payment-service",
        "environment": os.environ.get("ENVIRONMENT", "production"),
        "cluster_tier": "api-gateway",
        "region": os.environ.get("AWS_REGION", "us-east-1"),
        "version": "3.0.0"
    }


@app.get("/api/v1/services")
def services():
    """Enumerate the full 4-tier service topology for the demo dashboard."""
    return {
        "tiers": {
            "networking": ["vpc", "alb", "nat", "vpc-flow-logs", "security-groups"],
            "application": ["payment-api", "worker-fleet", "autoscaling", "api-gateway", "webhook-processor"],
            "data": ["postgres-primary", "postgres-read-replica", "redis-cache", "dynamodb-ledger", "secrets-manager"],
            "security": ["kms", "iam-boundary", "security-audit"],
        },
        "region": os.environ.get("AWS_REGION", "us-east-1"),
    }


@app.get("/api/v1/vault/status")
def vault_status():
    bucket = os.environ.get("CUSTOMER_DOCS_BUCKET", "acme-production-customer-vault-us-east-1")
    return {
        "vault_bucket": bucket,
        "encryption": "AWS-KMS (AES-256)",
        "status": "online"
    }


@app.get("/api/v1/ledger/status")
def ledger_status():
    table = os.environ.get("TRANSACTIONS_LEDGER", "acme-production-transactions-ledger")
    return {
        "ledger_table": table,
        "billing_mode": "PAY_PER_REQUEST",
        "pitr": "enabled",
        "status": "online"
    }


@app.get("/api/v1/queue/status")
def queue_status():
    queue = os.environ.get("PAYMENT_QUEUE_URL", "acme-production-payments-ingest")
    return {
        "queue": queue,
        "approach_depth": 0,
        "visibility_timeout_s": 60,
        "status": "online"
    }


@app.get("/api/v1/cache/status")
def cache_status():
    cluster = os.environ.get("SESSION_CACHE", "acme-production-session-cache")
    return {
        "cache_cluster": cluster,
        "engine": "redis",
        "nodes": 2,
        "status": "online"
    }


@app.get("/api/v1/workers/status")
def workers_status():
    asg = os.environ.get("WORKERS_ASG", "acme-production-workers-asg")
    return {
        "autoscaling_group": asg,
        "desired": 2,
        "min": 2,
        "max": 6,
        "multi_az": ["us-east-1a", "us-east-1b", "us-east-1c"],
        "role": "payment-processing",
        "status": "healthy"
    }


@app.get("/api/v1/db/status")
def db_status():
    return {
        "primary": os.environ.get("CORE_DB", "acme-production-core-postgres-cluster"),
        "read_replica": os.environ.get("CORE_DB_REPLICA", "acme-production-core-postgres-replica"),
        "engine": "postgres",
        "multi_az": True,
        "deletion_protection": True,
        "backup_retention_days": 30,
        "status": "online"
    }