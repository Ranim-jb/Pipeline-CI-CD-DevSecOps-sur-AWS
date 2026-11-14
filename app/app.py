from flask import Flask, jsonify
import os

app = Flask(__name__)

@app.get("/health")
def health():
    return jsonify(status="ok", service="devsecops-demo")

@app.get("/")
def index():
    return jsonify(
        message="API DevSecOps opérationnelle",
        service="devsecops-demo",
        environment=os.getenv("APP_ENV", "local"),
    )

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8080")))
