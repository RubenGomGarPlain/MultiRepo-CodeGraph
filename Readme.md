
# Objetivo principal

Quiero poder medir impacto sobre un listado de repositorios en github / azureDevops, etc..
Para ello quier usar esto https://marketplace.visualstudio.com/items?itemName=aStudioPlus.codegraph&ssr=false#overview

El flujo inicial, pero apto a ser modificado sería el siguiente:

# Flujo E2E completo
```
REPOS DE NEGOCIO
  repo-auth / repo-payments / repo-gateway / repo-notif / ...
  (solo contienen código — no saben nada del agente)
          │
          │ cualquier trigger
          ▼
─────────────────────────────────────────────────────
TRIGGER  (todos apuntan al mismo sitio)

  A) Dev abre PR en repo-auth
  B) Jira Automate detecta ticket nuevo / transición
  C) Dev escribe: @impact-agent "analiza AuthService"
  D) gh workflow run impact-check.yml --field symbol=AuthService
─────────────────────────────────────────────────────
          │
          ▼
GITHUB ACTIONS — impact-check.yml (en agents-repo)

  PASO 1 — Clonar todos los repos (shallow)
    git clone --depth 1 .../repo-auth     repos/repo-auth
    git clone --depth 1 .../repo-payments repos/repo-payments
    git clone --depth 1 .../repo-gateway  repos/repo-gateway
    (o restaurar desde cache si no han cambiado)

  PASO 2 — CodeGraph indexa todo el código
    codegraph-server --graph-only
      --workspace repos/repo-auth
      --workspace repos/repo-payments
      --workspace repos/repo-gateway
    → genera ~/.codegraph/graph.db (grafo cross-repo)

  PASO 3 — El agente ejecuta las tools
    Lee agents/impact-agent.md
    codegraph_pr_context()           → qué cambió
    codegraph_analyze_impact(symbol) → blast radius cross-repo
    codegraph_get_callers(symbol, depth:3)
    codegraph_find_related_tests(symbol)

  PASO 4 — Genera el resultado
    💥 Blast Radius: 3 repos, 12 funciones, 4 módulos
    🧪 Cobertura: 8/12 cubiertas — sin test: [verifyToken]
    ⚠️  Riesgo: ALTO — AuthService tiene 37 callers cross-repo
─────────────────────────────────────────────────────
          │
          ▼
DESTINO (según el trigger)

  A) PR abierto  → comentario automático en el PR
  B) Ticket Jira → comentario enriquecido en el ticket
  C) Copilot Chat → respuesta interactiva al dev
  D) Manual      → output en terminal / markdown