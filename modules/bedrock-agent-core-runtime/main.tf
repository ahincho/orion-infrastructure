###############################################################################
# Bedrock AgentCore Runtime: OrionAgentCore
# -----------------------------------------------------------------------------
# Provisiona el AgentRuntime + un AgentRuntimeEndpoint (alias).
#
# Cambios destructivos RequiresReplace:
#   - agent_runtime_name: cambio de nombre = recreate (stringplanmodifier.RequiresReplace).
#   - Cambio entre code_configuration <-> container_configuration en
#     agent_runtime_artifact: tambien = recreate.
#
# Network mode: PUBLIC por defecto. Para VPC mode (acceso privado a RDS), se
# requiere pasar subnets + security_groups. NO se anade `network_mode_config`
# en PUBLIC mode (provider lo rechaza si viene vacio en VPC, pero en PUBLIC
# lo ignora).
###############################################################################

resource "aws_bedrockagentcore_agent_runtime" "this" {
  agent_runtime_name = var.agent_runtime_name
  role_arn           = var.role_arn
  description        = var.description

  agent_runtime_artifact {
    container_configuration {
      container_uri = var.container_uri
    }
  }

  network_configuration {
    network_mode = var.network_mode

    # network_mode_config solo aplica cuando network_mode = "VPC".
    dynamic "network_mode_config" {
      for_each = var.network_mode == "VPC" ? [1] : []
      content {
        subnets         = toset(var.subnets)
        security_groups = toset(var.security_groups)
      }
    }
  }

  environment_variables = var.environment_variables

  tags = merge(var.tags, {
    Name        = var.agent_runtime_name
    Purpose     = "OrionAgentCoreAgentRuntime"
    Component   = "compute"
    Project     = var.project_name
    Environment = var.environment
  })
}

###############################################################################
# Endpoint: alias para invocaciones en runtime.
# Mismas restricciones de RequiresReplace en agent_runtime_id + name.
###############################################################################
resource "aws_bedrockagentcore_agent_runtime_endpoint" "this" {
  agent_runtime_id = aws_bedrockagentcore_agent_runtime.this.agent_runtime_id
  name             = var.endpoint_name
  description      = var.endpoint_description

  tags = merge(var.tags, {
    Name        = "${var.agent_runtime_name}-${var.endpoint_name}"
    Purpose     = "OrionAgentCoreEndpoint"
    Component   = "endpoint"
    Project     = var.project_name
    Environment = var.environment
  })
}
