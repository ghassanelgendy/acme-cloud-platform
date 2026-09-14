from fastapi import FastAPI, HTTPException
import os

app = FastAPI(title="Acme Payments API", version="2.4.0")

@app.get("/health")
def health():
    return {
        "status": "healthy",
        "service": "acme-payment-service",
        "environment": os.environ.get("ENVIRONMENT", "production"),
        "cluster_tier": "api-gateway",
        "region": os.environ.get("AWS_REGION", "us-east-1")
    }

@app.get("/api/v1/vault/status")
def vault_status():
    bucket = os.environ.get("CUSTOMER_DOCS_BUCKET", "acme-production-customer-vault-us-east-1")
    return {
        "vault_bucket": bucket,
        "encryption": "AES-256-KMS",
        "status": "online"
    }
