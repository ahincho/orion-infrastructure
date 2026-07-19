## Descripcion

<!-- Que cambio y por que. Incluir el modulo y/o capa afectada. -->

## Tipo

<!-- Marcar con x -->

- [ ] feat (nueva feature / modulo / recurso)
- [ ] fix (bugfix)
- [ ] chore (housekeeping sin cambio funcional)
- [ ] docs (solo documentacion)
- [ ] ci (cambio en workflows)

## Cambios

<!-- Lista de cambios principales (un bullet por modulo/archivo). -->

- 

## Validacion local

<!-- Confirmar checks antes de pedir review. -->

- [ ] `pre-commit run --all-files` paso
- [ ] `terraform fmt -recursive -diff` paso
- [ ] `terraform validate` paso en live/dev

## terraform plan esperado

<!-- Pegar output resumido de terraform plan para que el reviewer vea que
     cambios producira. Si no se ha corrido, dejarlo en blanco. -->

<details>
<summary>terraform plan (live/dev)</summary>

```
```

</details>

## Checklist

- [ ] El codigo sigue las convenciones de `AGENTS.md`
- [ ] Variables nuevas tienen `description` y `validation`
- [ ] Outputs nuevos tienen `description`
- [ ] Si se agrego un modulo nuevo, el `README.md` del modulo esta actualizado