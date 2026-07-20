# Module: iam-sam-deploy-dev

Crea el IAM role + inline policy `SamDeployPolicy` que asume el workflow
`CD - Deploy` de orion-backend via GitHub OIDC para correr `sam build`
y `sam deploy` contra AWS.

## Uso

```hcl
module "iam_sam_deploy_dev" {
  source = "../modules/iam-sam-deploy-dev"

  project_name     = "orion"
  environment      = "dev"
  aws_region       = "us-east-1"
  account_id       = "681526276858"
  github_org       = "ahincho"
  github_repo      = "orion-backend"
  github_branch    = "refs/heads/main"
  github_environments = ["dev"]
  s3_artifacts_bucket = "orion-sam-artifacts-dev"
}
```

## Outputs

- `role_arn` — usar como `AWS_DEPLOY_ROLE_ARN` en el GH Environment `dev`
  de orion-backend.
- `role_name` — `orion-sam-deploy-dev` (literal).
- `policy_name` — `SamDeployPolicy` (inline, 16 statements).

## Trust policy

- OIDC issuer: `arn:aws:iam::<account>:oidc-provider/token.actions.githubusercontent.com`
- Audience: `sts.amazonaws.com`
- Subject: `repo:<org>/orion-backend:ref:refs/heads/main*environment:<env>`
  (parametrizable via `github_environments`).

## SamDeployPolicy

16 statements (ver `main.tf`):

1. **CloudFormationReadAll** — `cloudformation:List*`/`Describe*`/`Get*` sobre `*`.
2. **CloudFormationManageOrionBackendStack** — `CreateStack`, `UpdateStack`,
   `DeleteStack`, `CreateChangeSet`, etc. sobre los ARN literal y
   wildcards `orion-backend-dev`, `orion-backend-prod`, `orion-backend-*`.
3. **LambdaReadAll** — `lambda:List*`/`GetAccountSettings` sobre `*`.
4. **LambdaManageFunctions** — `CreateFunction`, `UpdateFunctionCode`,
   `UpdateFunctionConfiguration`, etc. sobre `arn:aws:lambda:*:*:function:orion-*-dev`.
5. **LambdaManageLayers** — `PublishLayerVersion`, etc. sobre
   `layer:orion-node-{shared,runtime}-*-dev`.
6. **ApiGatewayV2Manage** — `CreateApi`, `CreateRoute`, `CreateIntegration`,
   `CreateAuthorizer`, etc. sobre `*`.
7. **EventBridgeManageBusAndRules** — `PutRule`, `PutTargets`, `CreateEventBus`,
   etc. sobre `rule/orion-*` + `event-bus/orion-*` + `archive/orion-*`.
8. **IAMManageExecutionRoles** — `iam:CreateRole`, `PutRolePolicy`, etc. sobre
   `role/orion-*`.
9. **IAMPassRoleToLambdaAndEvents** — `iam:PassRole` sobre `role/orion-*` con
   condition `iam:PassedToService in [lambda.amazonaws.com, apigateway.amazonaws.com, events.amazonaws.com]`.
10. **S3SamArtifacts** — `s3:GetObject`/`PutObject`/`ListBucket` sobre
    `arn:aws:s3:::<s3_artifacts_bucket>` y `/*`.
11. **SSMReadParameters** — `ssm:GetParameter(s)` sobre
    `parameter/orion/*`.
12. **KMSDecryptOrionKeys** — `kms:Decrypt`/`GenerateDataKey`/`DescribeKey`
    sobre `key/*`.
13. **CloudWatchLogsManage** — `logs:CreateLogGroup`/`PutRetentionPolicy`, etc.
    sobre `/aws/orion/dev/*` + `/aws/orion/*` + `/aws/lambda/orion-*-dev`.
14. **XRayTracing** — `xray:Put*`/`Get*` sobre `*`.
15. **STSGetCallerIdentity** — `sts:GetCallerIdentity` sobre `*` (para OIDC).
16. **SqsDLQ** — `sqs:CreateQueue`/`SendMessage`, etc. sobre
    `orion-backend-*-dev`.

## Notas

- `orion-backend-dev` se lista como ARN literal (no solo como wildcard
  `orion-backend-*-dev`) porque los wildcards SAM con segmentos
  intermedios no matchean el caso Phase 1.
- `default_tags` (Project, Environment, ManagedBy, Repository) se aplican
  via `live/dev/providers.tf` (definido en el caller, no en este modulo).
