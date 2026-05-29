# CodeGraph Org-Level Analysis — Comparativa de Aproximaciones

## TL;DR

| | A — Ephemeral | B — Cached | C — Container App |
|---|---|---|---|
| **Infraestructura** | Ninguna | Ninguna | Azure Container App |
| **Estado** | ❌ Sin estado | ✅ Cache Actions | ✅ Persistente |
| **Latencia 1er run** | ~2-5 min | ~2-5 min | ~10 min (deploy) + ~2-5 min (index) |
| **Latencia runs siguientes** | ~2-5 min | ⚡ ~15-30s (cache hit) | ⚡ <1s (grafo en memoria) |
| **Coste** | Solo CI minutes | Solo CI minutes | ~$15-30/mes (Container App min 1 replica) |
| **Multi-dev simultáneo** | ❌ Cada run es independiente | ❌ Cada run es independiente | ✅ Servidor compartido |
| **Copilot Chat interactivo** | ❌ Solo CI | ❌ Solo CI | ✅ MCP endpoint accesible desde VS Code |
| **Repos privados** | ✅ Con GH_PAT secret | ✅ Con GH_PAT secret | ✅ Con GH_PAT env var |
| **Complejidad setup** | ⭐ Mínima | ⭐⭐ Media | ⭐⭐⭐ Requiere Azure |

---

## A — Ephemeral (clone → index → run → borrar)

### Cómo funciona
```
workflow_dispatch(symbol=AuthService)
  └─ npm install @astudioplus/codegraph-mcp
  └─ git clone --depth 1 [todos los repos]
  └─ codegraph-server --graph-only --workspace repo-auth --workspace repo-payments ...
       --run-tool codegraph_analyze_impact --tool-args '{"symbol":"AuthService"}'
  └─ post resultado como comentario en PR
  └─ rm -rf repos/   ← limpieza, sin estado
```

### Cuándo usar
- POC inicial / primera demo con un cliente
- Repos pequeños (<500 ficheros por repo)
- No necesitas análisis frecuentes
- Quieres cero infraestructura y setup mínimo

### Limitaciones
- Re-indexa desde cero en cada run (tarda lo mismo siempre)
- No aprovechable desde Copilot Chat interactivo
- No escala bien con repos grandes (>2000 ficheros)

---

## B — Cached (actions/cache@v4 sobre `~/.codegraph/graph.db`)

### Cómo funciona
```
workflow_dispatch(symbol=AuthService)
  └─ git clone --depth 1 [todos los repos]
  └─ cache key = SHA256(HEAD de todos los repos concatenados)
  └─ actions/cache/restore → ~/.codegraph/graph.db
       ├─ CACHE HIT  → skip indexing (~15s total)
       └─ CACHE MISS → codegraph-server --graph-only [index] → save cache
  └─ codegraph-server --graph-only --run-tool codegraph_analyze_impact
  └─ post resultado en PR
```

### Cache key strategy
La cache key incluye el HEAD SHA de cada repo. Si cualquier repo hace push:
- Cache **miss** parcial → re-indexa solo lo necesario (CodeGraph es incremental)
- La `restore-keys` fallback permite reutilizar el grafo anterior como base

### Cuándo usar
- Repos medianos/grandes (1000-10000 ficheros)
- Análisis frecuentes (múltiples PRs al día)
- Quieres velocidad sin pagar infraestructura
- El equipo ya usa GitHub Actions intensivamente

### Limitaciones
- Cache de Actions tiene límite de 10GB por repo / 7 días de TTL
- No accesible desde Copilot Chat interactivo
- Primer run sigue siendo lento

---

## C — Azure Container App + supergateway → HTTP :3000

### Cómo funciona
```
Container App (siempre activo, min 1 replica):
  └─ entrypoint.sh
       └─ git clone todos los repos → /app/repos/
       └─ codegraph-server --graph-only --workspace ... [pre-index]
       └─ supergateway --port 3000 --stdio "codegraph-server --mcp --profile graph"
            ├─ POST /message  → MCP JSON-RPC calls
            ├─ GET  /sse      → Server-Sent Events (MCP protocol)
            └─ GET  /health   → health check

GitHub Actions (approach-c-trigger.yml):
  └─ curl -X POST $CONTAINER_APP_URL/message \
       -d '{"method":"tools/call","params":{"name":"codegraph_analyze_impact",...}}'
  └─ post resultado en PR

VS Code / Copilot Chat (cualquier dev):
  └─ mcp.json: { "url": "https://<app>.azurecontainerapps.io/sse" }
  └─ Copilot Chat puede usar todas las tools de CodeGraph en tiempo real
```

### Arquitectura del Container App
```
Azure Container App
├─ Image: codegraph-org (docker/Dockerfile)
├─ 2 vCPU / 4GB RAM
├─ Min replicas: 1 (siempre activo)
├─ Max replicas: 3 (escala por concurrencia HTTP)
├─ Volume: Azure File Share → /root/.codegraph (graph.db persistente)
└─ Secrets: GH_PAT
```

### Cuándo usar
- Orgs grandes (>10 repos, >50K ficheros)
- Múltiples devs necesitan análisis interactivo desde Copilot Chat
- Quieres un MCP endpoint permanente que Copilot use como herramienta nativa
- Tienes presupuesto Azure y quieres la experiencia más rápida

### Configurar Copilot Chat para usar el Container App
Añadir en `.vscode/mcp.json` del repo (o en `~/.claude.json` para Claude):
```json
{
  "servers": {
    "codegraph-org": {
      "url": "https://<app-name>.<region>.azurecontainerapps.io/sse"
    }
  }
}
```

### Limitaciones
- Requiere Azure subscription y coste mensual (~$15-30)
- Setup inicial más complejo (build imagen, push ACR, deploy Bicep)
- Si el container se reinicia, re-indexa desde cero (mitigado con Azure File Share)

---

## Guía de setup por aproximación

### Setup común (A, B y C)
1. Crear el `agents-repo` en GitHub
2. Añadir secret `GH_PAT` (PAT con `repo:read` sobre todos los repos del cliente)
3. Añadir variable `CODEGRAPH_ORG` con el nombre de la org
4. Editar `config/repos.yml` con la lista de repos

### Setup adicional para C
```bash
# 1. Build y push imagen al ACR (o GitHub Container Registry)
docker build -t codegraph-org ./docker
docker tag codegraph-org ghcr.io/<org>/codegraph-org:latest
docker push ghcr.io/<org>/codegraph-org:latest

# 2. Deploy infraestructura Azure
az group create -n rg-codegraph -l westeurope
az deployment group create \
  --resource-group rg-codegraph \
  --template-file infra/container-app.bicep \
  --parameters \
    githubPat="ghp_xxx" \
    githubOrg="my-org" \
    githubRepos="repo-auth repo-payments repo-gateway" \
    containerImage="ghcr.io/<org>/codegraph-org:latest"

# 3. Obtener la URL
az deployment group show \
  --resource-group rg-codegraph \
  --name container-app \
  --query properties.outputs.containerAppUrl.value -o tsv

# 4. Añadir la URL como variable en el repo de Actions
gh variable set CODEGRAPH_APP_URL --body "https://<app>.<region>.azurecontainerapps.io"
```

---

## Matriz de decisión

```
¿Tienes Azure y múltiples devs necesitan análisis interactivo?
  └─ SÍ → Aproximación C (Container App)
  └─ NO →
       ¿Repos grandes o análisis muy frecuentes (>5 PRs/día)?
         └─ SÍ → Aproximación B (Cached)
         └─ NO → Aproximación A (Ephemeral)
```
