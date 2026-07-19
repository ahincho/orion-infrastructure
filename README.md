# ORION -- orion-infrastructure-devops

Repositorio del proyecto **ORION** (Pequeno Sistema Cognitivo).

> Owner: @ahincho (solo)
> Repo: https://github.com/ahincho/orion-infrastructure-devops

## Estado

Este repositorio es parte del monorepo ORION. Estructura completa la decision arquitectonica de usar 5 repositorios (orion-*) coordinados por rama dev.

## Workflow de branching

- Branching: main (protegida) <- dev (integracion) <- eat/<scope>-<name>
- Toda PR va a dev; promover dev -> main requiere PR separado.
- Squash-only, branch deletion on merge.
- Reglas: rulesets aplican 3 reglas (deletion, non_fast_forward, required_linear_history). Sin pull_request rule (solo dev, no hay collaborators).
