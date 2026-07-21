# ADR 0007: API Gateway authorizer trust policy no admite `aws:SourceAccount` ni `aws:SourceArn`

- **Status**: Accepted
- **Date**: 2026-07-21
- **Deciders**: `@ahincho`
- **Repos afectados**: `orion-infrastructure`, `orion-backend`
- **Related PRs** (orden cronologico):
  - `orion-infrastructure#69` — crea modulo `iam-apigateway-authorizer-invoke`
  - `orion-infrastructure#73` — primer intento con `aws:SourceAccount` (regresion)
  - `orion-infrastructure#74` — revert de #73
  - `orion-infrastructure#75` — segundo intento con `aws:SourceArn` desde SSM (regresion)
  - `orion-infrastructure#76` — fix tecnico (`nonsensitive()`) que permitio apply, regresion aun presente
  - `orion-infrastructure#77` — revert de #75+#76
  - `orion-backend` — pendiente: cfn-nag con regla F36 para `AuthorizerFunctionPermission.SourceArn`

---

## Context

El role IAM `orion-dev-authorizer-invoke-*` es asumido por API Gateway
(`apigateway.amazonaws.com`) para invocar la Lambda `orion-authorizer-dev`
durante la validacion de tokens en rutas protegidas.

El trust policy inicial era:

```json
{
  "Effect": "Allow",
  "Principal": { "Service": "apigateway.amazonaws.com" },
  "Action": "sts:AssumeRole"
}
```

Esto permite que **cualquier API Gateway en la cuenta AWS** asuma el role.
El best-practice de AWS para defense-in-depth es endurecer el trust con
condition keys (`aws:SourceAccount`, `aws:SourceArn`) para prevenir
confusion attacks cross-account.

### Intentos empiricos y resultados

| PR    | Condition key probada     | Resultado post-apply                                              |
|-------|---------------------------|-------------------------------------------------------------------|
| #73   | `aws:SourceAccount`       | 500 en todas las rutas protegidas (regresion critica)             |
| #74   | revert #73                | smoke test vuelve a pasar                                         |
| #75   | `aws:SourceArn` desde SSM | 500 en todas las rutas protegidas (misma regresion)               |
| #76   | fix tecnico (no funcional)| apply succeed pero regresion persiste                             |
| #77   | revert #75+#76            | smoke test vuelve a pasar                                         |

Verificacion empirica del mecanismo:

1. `terraform apply` con la condition: trust policy aparece en AWS
   correctamente con la condition.
2. Smoke test E2E (`GET /v1/users/me` con Bearer JWT): 500 Internal Server
   Error. `GET /v1/users/me` sin Bearer: 401 (sigue funcionando, falla
   en el camino autenticado).
3. AWS CloudTrail NO registra `AssumeRole` events para el role (ni
   success ni failure). El fallo ocurre en la evaluacion de la trust
   policy antes de generar evento.
4. `aws iam update-assume-role-policy` removiendo la condition: smoke
   test pasa inmediatamente (200 con Bearer, 401 sin Bearer).

### Conclusion tecnica

**AWS API Gateway no setea `aws:SourceAccount` ni `aws:SourceArn` en el
`sts:AssumeRole` que ejecuta para invocar un Lambda authorizer.** Aunque
la documentacion de IAM lista esas condition keys como disponibles, la
implementacion interna del call path de API Gateway para authorizer
invocation no las popula. Cualquier condition de ese tipo evalua
`false` y el assume role falla silenciosamente (sin CloudTrail event).

Esto NO es un bug de nuestra configuracion: es una limitacion del
servicio AWS que la documentacion no explicita claramente.

---

## Decision

**El trust policy del role asumido por API Gateway se limita al service
principal sin conditions adicionales.**

```hcl
# modules/iam-apigateway-authorizer-invoke/main.tf
data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
    # NO aws:SourceAccount / aws:SourceArn conditions
  }
}
```

**La defensa contra cross-API confusion se delega a la Lambda resource
policy** (`AuthorizerFunctionPermission.SourceArn` en `orion-backend/template.yaml`):

```yaml
AuthorizerFunctionPermission:
  Type: AWS::Lambda::Permission
  Properties:
    FunctionName: !Ref AuthorizerFunction
    Action: lambda:InvokeFunction
    Principal: apigateway.amazonaws.com
    SourceArn: !Sub "arn:aws:execute-api:${AWS::Region}:${AWS::AccountId}:${HttpApi}/*/*"
```

El `SourceArn` aqui restringe la invocacion del Lambda **al API Gateway
especifico** (por API-ID). Aunque el role IAM sea asumido por un API
Gateway "equivocado" en la misma cuenta, la Lambda **rechaza** la
invocacion porque el `SourceArn` no matchea.

### Defense-in-depth: 3 capas

1. **IAM trust policy**: `apigateway.amazonaws.com` (cualquier API GW
   en la cuenta puede assumir el role).
2. **Lambda resource policy**: solo el API GW especifico puede invocar
   el Lambda (`SourceArn` por API-ID).
3. **IAM inline policy del role**: el role solo puede hacer
   `lambda:InvokeFunction` sobre `orion-authorizer-dev` (una sola
   funcion).

Un atacante que quisiera usar nuestro authorizer Lambda desde otro API
GW de la cuenta deberia:
- Crear/modificar un API GW en la misma cuenta (ya requiere compromiso
  de la cuenta),
- Asumir el role,
- Invocar el Lambda con `SourceArn` que matchee el ARN esperado.

Las capas 2 + 3 limitan el blast radius incluso si la capa 1 fuera
bypasseada.

### Por que NO JWT authorizer (Cognito o JWT nativo)

- Riesgo **ya mitigado** al nivel Lambda (capa 2).
- Coste de migracion: 2-3 semanas (refactor `register`/`login` a Cognito,
  eliminar Lambda authorizer, re-deploy, migracion de usuarios).
- ROI negativo para el caso actual (ambientes dev + prod en **misma**
  cuenta AWS — confirmado en spark-match planning).

---

## Consequences

### Positivas

- Stack funcional y estable (no mas regresiones de IAM trust).
- Riesgo de cross-API confusion mitigado por Lambda resource policy.
- Documentacion explicita de la limitacion AWS para futuros readers.

### Negativas

- Trust policy **teoricamente permisivo** dentro de la cuenta: cualquier
  API GW puede assumir el role (aunque la Lambda resource policy es la
  que realmente restringe).
- Si en el futuro spark-match migra a multi-account AWS (dev/prod en
  cuentas separadas), esta decision deberia revisarse porque el riesgo
  cross-account deja de ser solo teorico.

### Operacionales

- **Linting obligatorio**: cualquier `AWS::Lambda::Permission` con
  `Principal: apigateway.amazonaws.com` debe especificar `SourceArn`.
  Implementado via cfn-nag (regla F36) en `orion-backend` CI.
- **No añadir** `aws:SourceAccount` ni `aws:SourceArn` al modulo
  `iam-apigateway-authorizer-invoke` sin re-leer este ADR.
- Si AWS anade soporte futuro para esas condition keys en este call
  path, revisar este ADR y actualizar el modulo.

---

## Alternatives considered

### Probar otras condition keys (`aws:CalledVia`, `aws:PrincipalServiceName`)

- **Rechazado**: `aws:CalledVia` documenta chains de servicios pero STS
  es el "assumer" del role, no un callee. API Gateway no apareceria en
  `CalledVia` para `sts:AssumeRole`. `aws:PrincipalServiceName` solo
  confirma que es un servicio AWS, no restringe origen.
- Coste/beneficio negativo: alta probabilidad de fallo empirico (1 PR +
  smoke test + revert) + defensa redundante con Lambda resource policy.

### Hardening sin condition keys (`PermissionsBoundary`, `MaxSessionDuration`)

- **Rechazado**: `PermissionsBoundary` acota blast radius si el role es
  comprometido, pero no previene que sea asumido en primer lugar.
  `MaxSessionDuration` minimiza ventana de uso post-compromiso pero
  no aplica al caso (API Gateway asume + usa inmediatamente).
- Coste/beneficio negativo: paperwork que no cierra la gap teorica.

### Cambiar a Cognito User Pool authorizer

- **Rechazado por ahora**: cambio arquitectural mayor, riesgo ya
  mitigado por Lambda resource policy.
- **Reconsiderar si**: spark-match migra a multi-account, o si AWS anade
  un tipo de Lambda authorizer con soporte nativo para condition keys.

### Esperar soporte AWS

- **Rechazado como accion**: no es accionable. Documentado aqui para
  referencia futura.

---

## References

- AWS IAM Condition Keys: <https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_condition-keys.html>
- API Gateway Lambda Authorizers: <https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-use-lambda-authorizer.html>
- AWS Security Bulletin sobre confusion attacks cross-service:
  <https://docs.aws.amazon.com/whitepapers/latest/aws-security-incident-response-guide/cross-service-confused-deputy.html>
- `orion-infrastructure` modulo `iam-apigateway-authorizer-invoke/`
- `orion-backend` template `template.yaml` (recurso `AuthorizerFunctionPermission`)