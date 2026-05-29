# 💥 Análisis de Impacto — Eliminar sección `Activity` de Advisor Management

> **Solicitud original (issue #1):** "Quiero quitar la sección de Activity en Advisor Management. ¿Qué impacto tendría?"
>
> Este documento recoge la metodología de análisis y las áreas de riesgo a revisar
> antes de proceder con la eliminación.

---

## Cómo ejecutar el análisis completo

Lanza el workflow de GitHub Actions apuntando al símbolo `Activity`:

```bash
# Approach A — efímero (sin infraestructura previa)
gh workflow run approach-a-ephemeral.yml \
  --field symbol=Activity \
  --field output_format=markdown

# Approach C — Container App (si está desplegado)
gh workflow run approach-c-trigger.yml \
  --field symbol=Activity
```

> **Nota sobre `depth`:** el parámetro `depth` en las llamadas a `codegraph_analyze_impact`
> y `codegraph_get_callers` controla la profundidad de la búsqueda transitiva en el grafo
> de dependencias. `depth=1` devuelve solo los llamantes directos; `depth=3` expande hasta
> tres niveles de dependencia transitiva (A→B→C→D), lo que suele ser suficiente para
> obtener el blast radius real sin generar ruido excesivo.

O bien, desde Copilot Chat en el repositorio:

> @copilot analiza el impacto de `Activity` en advisor-management

---

## Áreas de impacto esperadas

Las siguientes categorías son las que CodeGraph identificará al ejecutar
`codegraph_analyze_impact` sobre el símbolo `Activity`:

### 1. Componentes UI directamente acoplados

| Riesgo | Qué buscar |
|--------|------------|
| 🔴 ALTO | Componentes padre que renderizan `<ActivitySection>` / `<Activity>` |
| 🟡 MEDIO | Hooks o contextos que exponen datos de actividad (p. ej. `useActivity`) |
| 🟢 BAJO  | Utilidades de formato/fecha usadas exclusivamente por Activity |

### 2. Llamadas a API / servicios backend

| Riesgo | Qué buscar |
|--------|------------|
| 🔴 ALTO | Endpoints exclusivos de actividad que quedarían sin consumidor |
| 🟡 MEDIO | Endpoints compartidos con otras secciones (feed, timeline, logs) |
| 🟢 BAJO  | Constantes de ruta o tipos TypeScript exclusivos de Activity |

### 3. Estado global (Redux / Zustand / Context)

| Riesgo | Qué buscar |
|--------|------------|
| 🔴 ALTO | Slices o reducers cuya única fuente de consumo es la sección Activity |
| 🟡 MEDIO | Selectores referenciados también desde otras secciones |
| 🟢 BAJO  | Acciones de analytics/tracking asociadas exclusivamente a Activity |

### 4. Rutas de navegación

| Riesgo | Qué buscar |
|--------|------------|
| 🔴 ALTO | Rutas que apuntan directamente a la vista Activity (deep-links, emails) |
| 🟡 MEDIO | Guards de navegación o breadcrumbs que incluyen Activity |

### 5. Tests existentes

Los tests vinculados a `Activity` que quedarán **huérfanos** y deberán eliminarse
o adaptarse:

- Tests unitarios del componente `Activity` / `ActivityList` / `ActivityItem`
- Tests de integración que navegan hasta la sección Activity
- Tests E2E con rutas como `/advisor/:id/activity`

---

## Checklist de seguridad antes de eliminar

- [ ] Ejecutar `codegraph_analyze_impact(symbol="Activity", depth=3)` y revisar el blast radius completo
- [ ] Confirmar con `codegraph_get_callers(depth=3)` que ningún módulo externo (repo `skills` u otros) importa símbolos de Activity
- [ ] Verificar con `codegraph_find_related_tests` todos los tests afectados
- [ ] Revisar si existen **feature flags** que controlen la visibilidad de la sección (opción de desactivar sin eliminar código)
- [ ] Comprobar si hay **permisos / roles** ligados a la sección Activity (p. ej. `canViewActivity`)
- [ ] Actualizar la documentación de usuario / Storybook si existe

---

## Clasificación de riesgo provisional

> ⚠️ Sin ejecutar el análisis real de CodeGraph sobre el repo privado, la clasificación
> es orientativa. Ejecuta el workflow para obtener datos precisos.

| Dimensión | Riesgo estimado | Justificación |
|-----------|-----------------|---------------|
| Callers directos | 🟡 MEDIO | Secciones de navegación y dashboards suelen referenciar Activity |
| Callers cross-repo | 🟢 BAJO | Actividad es típicamente un módulo interno |
| Cobertura de tests | 🟡 MEDIO | Las vistas de actividad suelen tener tests E2E |
| Datos en BD / API | 🔴 ALTO | Endpoints/tablas de actividad pueden tener dependencias no visibles en el código |

**Riesgo global estimado: MEDIO** — proceder con la eliminación por fases:
1. Ocultar la sección con feature flag
2. Verificar métricas de uso en producción
3. Eliminar el código tras confirmar impacto cero

---

## Referencias

- Runbook del agente: [`agents/impact-agent.md`](../agents/impact-agent.md)
- Configuración de repos: [`config/repos.yml`](../config/repos.yml)
- Workflow efímero: [`.github/workflows/approach-a-ephemeral.yml`](../.github/workflows/approach-a-ephemeral.yml)
