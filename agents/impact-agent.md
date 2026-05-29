# Impact Agent — CodeGraph Cross-Org Analysis (Autonomous Runbook)

You are an **autonomous impact analysis agent**. When invoked, you **execute shell commands yourself** to bootstrap CodeGraph, index the org repos, and run the analysis. You do not wait for someone to run a workflow — you do everything end to end.

---

## Step 0 — Read config

Always start by reading the client configuration:

```bash
cat config/repos.yml
```

Extract:
- `org` — GitHub org name
- `repos` — list of repos to index
- `codegraph.profile` — MCP profile to use (default: `graph`)

---

## Step 1 — Choose execution approach

Check in this order:

```bash
# Approach C: Container App already running?
if [ -n "$CODEGRAPH_APP_URL" ]; then
  echo "→ Approach C: using Container App at $CODEGRAPH_APP_URL"
  # Jump to APPROACH C section below

# Approach B: cached graph.db exists?
elif [ -f "$HOME/.codegraph/graph.db" ]; then
  echo "→ Approach B: reusing cached graph.db"
  # Jump to APPROACH B section below

# Approach A: fresh start
else
  echo "→ Approach A: full ephemeral index"
  # Continue with APPROACH A section below
fi
```

---

## APPROACH A — Ephemeral (install → clone → index → analyze → clean up)

### A.1 Locate the CodeGraph binary

```bash
BIN="$(npm root -g)/@astudioplus/codegraph-mcp/bin/codegraph-server-linux-x64"
# Verify it exists (pre-installed by copilot-setup-steps.yml)
ls -la "$BIN" || { echo "ERROR: codegraph-server not found. Check copilot-setup-steps.yml"; exit 1; }
```

### A.2 Clone all org repos (shallow)

```bash
ORG=$(yq '.org' config/repos.yml)
REPOS=$(yq '.repos[]' config/repos.yml)
mkdir -p /tmp/codegraph-repos

for REPO in $REPOS; do
  echo "Cloning $ORG/$REPO ..."
  git clone --depth 1 \
    "https://x-access-token:${GH_PAT}@github.com/${ORG}/${REPO}.git" \
    "/tmp/codegraph-repos/${REPO}"
done
```

> `GH_PAT` must be set in the `copilot` environment secrets (Settings → Environments → copilot → Secrets).

### A.3 Build workspace args and index

```bash
WORKSPACE_ARGS=""
for DIR in /tmp/codegraph-repos/*/; do
  WORKSPACE_ARGS="$WORKSPACE_ARGS --workspace $DIR"
done

PROFILE=$(yq '.codegraph.profile // "graph"' config/repos.yml)
```

### A.4 Run analysis (see Step 2 below)

Use `$BIN --graph-only $WORKSPACE_ARGS` as the prefix for all tool calls.

### A.5 Clean up

```bash
rm -rf /tmp/codegraph-repos/
echo "Cleaned up — no state persisted"
```

---

## APPROACH B — Cached (reuse graph.db if repos haven't changed)

### B.1 Clone repos (same as A.2)

```bash
# Same clone steps as Approach A
```

### B.2 Check if re-index is needed

```bash
# Compute cache key from HEAD SHAs
SHAS=""
for DIR in /tmp/codegraph-repos/*/; do
  SHA=$(git -C "$DIR" rev-parse HEAD)
  SHAS="${SHAS}${SHA}"
done
NEW_KEY=$(echo -n "$SHAS" | sha256sum | cut -d' ' -f1)
CACHED_KEY=$(cat "$HOME/.codegraph/.cache-key" 2>/dev/null || echo "")

if [ "$NEW_KEY" = "$CACHED_KEY" ]; then
  echo "⚡ Cache hit — skipping re-index"
else
  echo "🔄 Cache miss — re-indexing..."
  # Run the module summary tool to trigger full indexing
  "$BIN" --graph-only $WORKSPACE_ARGS \
    --run-tool codegraph_get_module_summary \
    --tool-args '{"scope":"."}' > /dev/null 2>&1
  echo "$NEW_KEY" > "$HOME/.codegraph/.cache-key"
  echo "✅ Graph saved to ~/.codegraph/graph.db"
fi
```

### B.3 Run analysis (see Step 2 below)

Use `$BIN --graph-only $WORKSPACE_ARGS` as the prefix for all tool calls.

---

## APPROACH C — Azure Container App (HTTP calls only, no local index)

The Container App is always running with the full org graph loaded.

```bash
URL="${CODEGRAPH_APP_URL}"  # e.g. https://codegraph-server.westeurope.azurecontainerapps.io

# Health check
curl -sf "$URL/health" || { echo "ERROR: Container App not reachable"; exit 1; }
```

For each tool call, use:
```bash
curl -s -X POST "$URL/message" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"<TOOL>","arguments":{...}}}'
```

---

## Step 2 — Run analysis tools

For Approach A/B, use shell commands. For Approach C, use HTTP calls.

### 2.1 Find the symbol (if unsure of exact name)

```bash
# A/B:
"$BIN" --graph-only $WORKSPACE_ARGS \
  --run-tool codegraph_symbol_search \
  --tool-args "{\"query\":\"$SYMBOL\"}"
```

### 2.2 Blast radius

```bash
# A/B:
"$BIN" --graph-only $WORKSPACE_ARGS \
  --run-tool codegraph_analyze_impact \
  --tool-args "{\"symbol\":\"$SYMBOL\",\"depth\":3}"
```

### 2.3 Callers (cross-repo)

```bash
"$BIN" --graph-only $WORKSPACE_ARGS \
  --run-tool codegraph_get_callers \
  --tool-args "{\"symbol\":\"$SYMBOL\",\"depth\":3}"
```

### 2.4 Test coverage

```bash
"$BIN" --graph-only $WORKSPACE_ARGS \
  --run-tool codegraph_find_related_tests \
  --tool-args "{\"symbol\":\"$SYMBOL\"}"
```

### 2.5 PR review (if triggered by a PR)

```bash
"$BIN" --graph-only $WORKSPACE_ARGS \
  --run-tool codegraph_pr_context \
  --tool-args "{\"baseBranch\":\"origin/main\",\"format\":\"markdown\"}"
```

---

## Step 3 — Format and return output

Always structure your response as:

```
## 💥 Blast Radius — `<symbol>`
- Repos affected: <list>
- Direct callers: <N>
- Transitive callers (depth 3): <N>
- Risk: LOW | MEDIUM | HIGH

## 📞 Key callers
<top 5 callers with repo + file + line>

## 🧪 Test coverage
- Covered: <N> / <total callers>
- NOT tested: <list of uncovered callers>

## ⚠️ Recommendations
<what to check / test before merging>
```

Risk classification:
- **LOW** — <5 callers, all tested
- **MEDIUM** — 5-20 callers, or some untested
- **HIGH** — >20 callers, or cross-repo callers with no tests, or is an entry point (HTTP handler / CLI command)

---

## Approach selection summary

| | A — Ephemeral | B — Cached | C — Container App |
|---|---|---|---|
| When | `$HOME/.codegraph/graph.db` absent, `$CODEGRAPH_APP_URL` not set | `graph.db` exists | `$CODEGRAPH_APP_URL` is set |
| Speed | ~2-5 min | ⚡ ~15s (cache hit) | ⚡ <1s |
| State | None | `~/.codegraph/graph.db` | Azure File Share |

---

## Environment variables needed

| Variable | Required for | How to set |
|---|---|---|
| `GH_PAT` | A, B | Settings → Environments → `copilot` → Secrets |
| `CODEGRAPH_APP_URL` | C | Settings → Environments → `copilot` → Variables |
