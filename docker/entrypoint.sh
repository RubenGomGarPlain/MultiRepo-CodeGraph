#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# entrypoint.sh — Clone repos, index with CodeGraph, expose via supergateway
#
# Environment variables:
#   GH_PAT            GitHub Personal Access Token (required for private repos)
#   CODEGRAPH_ORG     GitHub org name (default: my-org)
#   CODEGRAPH_REPOS   Space-separated list of repo names (default: empty)
#   CODEGRAPH_PROFILE MCP tool profile: all|core|graph|memory (default: graph)
#   PORT              HTTP port for supergateway (default: 3000)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

ORG="${CODEGRAPH_ORG:-my-org}"
REPOS="${CODEGRAPH_REPOS:-}"
PROFILE="${CODEGRAPH_PROFILE:-graph}"
PORT="${PORT:-3000}"
REPOS_DIR="/app/repos"

# ── Resolve binary ────────────────────────────────────────────────────────────
BIN="$(npm root -g)/@astudioplus/codegraph-mcp/bin/codegraph-server-linux-x64"
if [ ! -f "$BIN" ]; then
  echo "ERROR: codegraph-server binary not found at $BIN"
  exit 1
fi

# ── Clone repos ───────────────────────────────────────────────────────────────
mkdir -p "$REPOS_DIR"
if [ -n "$REPOS" ]; then
  for REPO in $REPOS; do
    DEST="$REPOS_DIR/$REPO"
    if [ -d "$DEST/.git" ]; then
      echo "↻ Updating $ORG/$REPO ..."
      git -C "$DEST" pull --ff-only --quiet || true
    else
      echo "⬇ Cloning $ORG/$REPO ..."
      if [ -n "${GH_PAT:-}" ]; then
        git clone --depth 1 \
          "https://x-access-token:${GH_PAT}@github.com/${ORG}/${REPO}.git" \
          "$DEST"
      else
        git clone --depth 1 \
          "https://github.com/${ORG}/${REPO}.git" \
          "$DEST"
      fi
    fi
  done
  echo "✅ All repos ready in $REPOS_DIR"
else
  echo "⚠️  CODEGRAPH_REPOS is empty — starting with empty workspace"
fi

# ── Build workspace args ──────────────────────────────────────────────────────
WORKSPACE_ARGS=""
for DIR in "$REPOS_DIR"/*/; do
  if [ -d "$DIR" ]; then
    WORKSPACE_ARGS="$WORKSPACE_ARGS --workspace $DIR"
  fi
done

if [ -z "$WORKSPACE_ARGS" ]; then
  echo "⚠️  No workspaces found — CodeGraph will index current directory"
fi

# ── Pre-index (warm up graph.db before accepting connections) ─────────────────
if [ -f "$HOME/.codegraph/graph.db" ]; then
  echo "⚡ Existing graph.db found — skipping full re-index"
else
  echo "📊 Pre-indexing workspaces (this may take a moment)..."
  "$BIN" \
    --graph-only \
    $WORKSPACE_ARGS \
    --run-tool codegraph_get_module_summary \
    --tool-args '{"scope":"."}' \
    > /dev/null 2>&1 || true
  echo "✅ Pre-index complete"
fi

# ── Start MCP server piped through supergateway ───────────────────────────────
echo "🚀 Starting CodeGraph MCP server → supergateway on :${PORT}"
echo "   Profile: $PROFILE"
echo "   Workspaces: $WORKSPACE_ARGS"

# supergateway wraps the stdio MCP server and exposes:
#   POST /message  → MCP JSON-RPC calls
#   GET  /sse      → Server-Sent Events stream (MCP protocol)
#   GET  /health   → Health check endpoint
exec supergateway \
  --port "$PORT" \
  --stdio "$BIN --mcp --profile $PROFILE $WORKSPACE_ARGS"
