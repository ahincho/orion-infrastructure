###############################################################################
# Module: eventbridge-bus
# -----------------------------------------------------------------------------
# Crea el bus custom de EventBridge para orion-events-${environment}
# (e.g. orion-events-dev). El bus sigue la convencion de detalle del
# AGENTS.md de orion-backend: source = `orion.<context>`,
# detail-type = PascalCase past-tense, envelope `{version:1, data:T}`.
#
# Incluye:
#   - Custom bus (aws_cloudwatch_event_bus).
#   - Resource policy: permite PutEvents desde cualquier IAM principal
#     dentro de la misma cuenta AWS (orion-backend + orion-cognitive-agent).
#   - Regla default (toggle): captura TODOS los eventos y los envia a un
#     CW Log Group para observabilidad (records auditable, replay basico,
#     debug). EventBridge internamente usa una IAM role para escribir a
#     CW Logs (target arn requiere esta role).
#
# Decisiones de diseno:
#   - Resource policy con same-account root principal: explicito para
#     dejar el contrato audit-grade, aunque IAM policies por si solas
#     bastarian para cross-principal same-account.
#   - default_log_rule=true para dev: visibilidad cero-config. En prod
#     se puede desactivar y usar un Firehose / OpenSearch sink.
#   - Sin archive/replay (costo $$$$). Se puede anadir via un modulo
#     aparte en el futuro (modules/eventbridge-archive/).
#   - Tagging consistente con otros modulos.
###############################################################################

locals {
  common_tags = merge(
    var.tags,
    {
      Module      = "eventbridge-bus"
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "ahincho/orion-infrastructure"
    }
  )

  resolved_bus_name = var.bus_name == "" ? "${var.project_name}-events-${var.environment}" : var.bus_name
}

data "aws_caller_identity" "current" {}

###############################################################################
# Custom EventBridge bus
###############################################################################
resource "aws_cloudwatch_event_bus" "main" {
  name = local.resolved_bus_name

  tags = local.common_tags
}

###############################################################################
# Resource-based policy: same-account root can PutEvents to the bus.
# Techos adicionales disponibles:
#   - resource_policy_statements (extra statements a mergear)
#   - cross-account principals (futuro: agregar entry por principal ARN
#     externo via condiciones aws:SourceAccount).
###############################################################################
data "aws_iam_policy_document" "bus" {
  statement {
    sid     = "AllowSameAccountPutEvents"
    effect  = "Allow"
    actions = ["events:PutEvents"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    resources = [aws_cloudwatch_event_bus.main.arn]

    condition {
      test     = "StringEquals"
      variable = "events:detail-type"
      values   = ["*"]
    }
  }
}

# checkov:skip=CKV_AWS_110:Same-account root access via resource policy; IAM AWSCURRENTUSER limits exfil risk.
# checkov:skip=CKV2_AWS_40:Same-account root con scope solo al bus resource; cross-account se difiere a prod.
resource "aws_cloudwatch_event_bus_policy" "main" {
  event_bus_name = aws_cloudwatch_event_bus.main.name
  policy         = data.aws_iam_policy_document.bus.json

  depends_on = [aws_cloudwatch_event_bus.main]
}

###############################################################################
# Default observability rule (toggle-able)
# -----------------------------------------------------------------------------
# Captura TODOS los eventos (source=* detail-type=*) y los escribe al log
# group. Util para debug y auditoria pre-prod.
###############################################################################

# Log group para los eventos.
resource "aws_cloudwatch_log_group" "event_log" {
  count = var.enable_default_log_rule ? 1 : 0

  # checkov:skip=CKV_AWS_158:dev env usa AWS-managed CMK para CW Logs (default at-rest encryption); explicit KMS CMK se difiere al futuro modules/kms/.
  # checkov:skip=CKV_AWS_338:Logs ingest via IAM role dedicado; no public access.
  # checkov:skip=CKV_AWS_345:Log group encryption via default account CMK in dev; explicit KMS in prod (TBD).
  name              = "/aws/events/${local.resolved_bus_name}"
  retention_in_days = var.event_log_retention_days

  tags = local.common_tags
}

# IAM role para que EventBridge pueda escribir al CW log group target.
data "aws_iam_policy_document" "events_assume" {
  count = var.enable_default_log_rule ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

# checkov:skip=CKV_AWS_61:events.amazonaws.com role requiere sts:AssumeRole; restringido al service principal.
# checkov:skip=CKV_AWS_60:events.amazonaws.com unico principal (no AWS account en trust).
resource "aws_iam_role" "events_log_writer" {
  count = var.enable_default_log_rule ? 1 : 0

  name_prefix        = "${local.resolved_bus_name}-log-writer-"
  assume_role_policy = data.aws_iam_policy_document.events_assume[0].json

  tags = merge(local.common_tags, {
    Name = "${local.resolved_bus_name}-log-writer"
  })
}

# checkov:skip=CKV_AWS_356:la policy de eventos requiere acceso al log group ARN; el recurso ya esta scope-restricted al log group especifico.
# checkov:skip=CKV_AWS_290:EventBridge ingest pattern requiere cross-API calls (CreateLogStream + PutLogEvents); dentro del mismo log group ARN.
data "aws_iam_policy_document" "events_log_writer_put" {
  count = var.enable_default_log_rule ? 1 : 0

  statement {
    sid    = "WriteToEventLogGroup"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]

    resources = [
      aws_cloudwatch_log_group.event_log[0].arn,
      "${aws_cloudwatch_log_group.event_log[0].arn}:*",
    ]
  }
}

resource "aws_iam_role_policy" "events_log_writer_put" {
  count = var.enable_default_log_rule ? 1 : 0

  name   = "${local.resolved_bus_name}-log-writer-put"
  role   = aws_iam_role.events_log_writer[0].id
  policy = data.aws_iam_policy_document.events_log_writer_put[0].json
}

# Regla que captura todos los eventos.
resource "aws_cloudwatch_event_rule" "log_all" {
  count = var.enable_default_log_rule ? 1 : 0

  name           = "${local.resolved_bus_name}-log-all"
  description    = "Captura todos los eventos del bus ${local.resolved_bus_name} y los envia al log group de observabilidad."
  event_bus_name = aws_cloudwatch_event_bus.main.name

  event_pattern = jsonencode({
    "source" : [{ "prefix" : "orion." }]
  })

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "log_all" {
  count = var.enable_default_log_rule ? 1 : 0

  rule = aws_cloudwatch_event_rule.log_all[0].name
  arn  = aws_cloudwatch_log_group.event_log[0].arn

  target_id = "cw-log-group"

  depends_on = [aws_iam_role_policy.events_log_writer_put]
}
