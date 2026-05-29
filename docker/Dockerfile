# ─────────────────────────────────────────────────────────────────────────────
# CodeGraph org-level MCP server + supergateway
#
# Starts codegraph-server (MCP stdio) and pipes it through supergateway
# to expose an HTTP/SSE endpoint on port 3000.
#
# On startup:
#   1. Clone all repos specified in CODEGRAPH_REPOS env var
#   2. Start codegraph-server --mcp with all workspaces
#   3. Pipe through supergateway on :3000
#
# Usage:
#   docker build -t codegraph-org .
#   docker run -p 3000:3000 \
#     -e GH_PAT=ghp_xxx \
#     -e CODEGRAPH_ORG=my-org \
#     -e CODEGRAPH_REPOS="repo-auth repo-payments repo-gateway" \
#     codegraph-org
# ─────────────────────────────────────────────────────────────────────────────
FROM node:20-slim

# Install system deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install CodeGraph MCP server (pre-built binary via npm — no Rust needed)
RUN npm install -g @astudioplus/codegraph-mcp

# Install supergateway — wraps MCP stdio server as HTTP/SSE
RUN npm install -g supergateway

# Copy entrypoint
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# CodeGraph graph persistence (mount a volume here for persistence across restarts)
VOLUME ["/root/.codegraph"]

# MCP-over-HTTP port
EXPOSE 3000

# Health check — supergateway exposes /health
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD curl -f http://localhost:3000/health || exit 1

ENTRYPOINT ["/app/entrypoint.sh"]
