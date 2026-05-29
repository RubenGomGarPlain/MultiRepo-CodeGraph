# Copilot Agent Instructions — CodeGraph Impact Analysis

This repo contains an **autonomous impact analysis agent** for org-level code analysis using CodeGraph.

## When to act

Respond to requests like:
- "analyze impact of `AuthService`"
- "what breaks if I change `PaymentProcessor`?"
- "review this PR for blast radius"
- "who calls `verifyToken` across all repos?"

## How to act

**Always follow the runbook in `agents/impact-agent.md` step by step.**

1. Read `config/repos.yml` to get the org and repos
2. Choose the execution approach (A, B or C) as described in the runbook
3. Run the shell commands yourself — do not ask the user to run them
4. Return the formatted analysis

## Key facts

- CodeGraph binary is pre-installed at: `$(npm root -g)/@astudioplus/codegraph-mcp/bin/codegraph-server-linux-x64`
- `yq` is pre-installed for parsing YAML config
- `GH_PAT` is available as an environment secret for cloning private repos
- `CODEGRAPH_APP_URL` (if set) means use Approach C — skip local indexing entirely
