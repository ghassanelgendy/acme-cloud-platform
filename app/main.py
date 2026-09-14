from fastapi import FastAPI, HTTPException
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
import os

app = FastAPI(title="Acme Payments API", version="2.4.0")

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
