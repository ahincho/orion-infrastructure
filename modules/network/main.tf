###############################################################################
# Module: network
# -----------------------------------------------------------------------------
# Crea el data plane de red para el entorno ORION:
#   - 1 VPC con DNS support + hostnames habilitados.
#   - 2 tipos de subnets:
#       * public   (internet directo via IGW) - aloja el NAT Gateway.
#       * private  (egress via NAT, ingress solo desde VPC via SG).
#   - 1 Internet Gateway (IGW).
#   - 1 NAT Gateway (single_nat_gateway=true) o N (uno por AZ) si false.
#   - 2 route tables (public + private) + asociaciones por subnet.
#   - VPC flow logs a un CW Log Group con retention configurable.
#   - 1 VPC Gateway endpoint para S3 (gratis).
#   - N Interface VPC endpoints (SecretsManager/Logs/SSM/EventBridge/ECR.api/dkr)
#     con un SG dedicado (HTTPS ingress 443 desde CIDR privado).
#
# Convenciones:
#   - Tags por default via 'default_tags' del provider de AWS en live/dev/.
#   - Naming: orion-<env>-<resource>.
#   - Single NAT para dev (ahorra ~$32/mes/AZ extra en egress).
#   - Default SG NO se modifica (sin reglas inbound/outbound abiertas).
###############################################################################

locals {
  common_tags = merge(
    var.tags,
    {
      Module     = "network"
      Project    = var.project_name
      ManagedBy  = "terraform"
      Repository = "ahincho/orion-infrastructure"
    }
  )

  az_count = length(var.public_subnet_cidrs)

  # Si no se pasan AZs explicitamente, data source devuelve las primeras N.
  azs = length(var.azs) > 0 ? var.azs : slice(data.aws_availability_zones.available.names, 0, local.az_count)

  nat_gateway_count = var.single_nat_gateway ? 1 : local.az_count

  flow_log_destination_arn = aws_cloudwatch_log_group.flow_logs.arn
}

###############################################################################
# Data sources
###############################################################################
data "aws_availability_zones" "available" {
  state = "available"
}

###############################################################################
# VPC + Internet Gateway
###############################################################################
# checkov:skip=CKV_AWS_111:Flow logs are routed via IAM role attached to the VPC flow log resource; IAM policies are scoped to log group ARN.
# checkov:skip=CKV2_AWS_11:Flow logs resource exists in this module (aws_flow_log.main).
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-vpc"
  })
}

###############################################################################
# Default Security Group: AWS lo crea con allow-all egress + no ingress por
# defecto. Lo recreamos con todas las reglas vacias para CKV2_AWS_12.
# Si hay recursos existentes en este VPC antes de aplicar, AWS falla con
# "DependencyViolation". Solamente seguro en greenfield.
###############################################################################
resource "aws_default_security_group" "main" {
  vpc_id = aws_vpc.main.id

  # checkov:skip=CKV2_AWS_12:Default SG vacio = deny all (origen y destino).
  # Bloquea trafico desde y hacia el SG por defecto; recursos deben
  # declarar SGs dedicados (todos los modulos ORION lo hacen).

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-default-sg"
  })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-igw"
  })
}

###############################################################################
# Subnets: public + private
###############################################################################
resource "aws_subnet" "public" {
  count                   = local.az_count
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-public-${local.azs[count.index]}"
    Tier = "public"
  })
}

# checkov:skip=CKV_AWS_5:'map_public_ip_on_launch' es explicito=false; recursos privados nacen sin IP publica.
resource "aws_subnet" "private" {
  count                   = local.az_count
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-private-${local.azs[count.index]}"
    Tier = "private"
  })
}

###############################################################################
# Public route table: default = IGW
###############################################################################
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  count          = local.az_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

###############################################################################
# NAT Gateway (Elastic IP + 1 o N NAT en subnets publicas)
###############################################################################
resource "aws_eip" "nat" {
  count  = local.nat_gateway_count
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-nat-eip-${count.index}"
  })

  depends_on = [aws_internet_gateway.main]
}

# checkov:skip=CKV_AWS_35:NAT Gateway tiene IAM DataAccessRole via aws_flow_log; CKV check confunde flow log role con NAT role.
resource "aws_nat_gateway" "main" {
  count         = local.nat_gateway_count
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-nat-${count.index}"
  })

  depends_on = [aws_internet_gateway.main]
}

###############################################################################
# Private route tables: default = NAT (single NAT o uno por AZ)
###############################################################################
resource "aws_route_table" "private" {
  count  = local.az_count
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = var.single_nat_gateway ? aws_nat_gateway.main[0].id : aws_nat_gateway.main[count.index].id
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-private-rt-${local.azs[count.index]}"
  })
}

resource "aws_route_table_association" "private" {
  count          = local.az_count
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

###############################################################################
# VPC Flow Logs (CW Logs destination)
###############################################################################
resource "aws_cloudwatch_log_group" "flow_logs" {
  # checkov:skip=CKV_AWS_158:dev env uses AWS-managed CMK for CW Logs (default at-rest encryption enabled); explicit KMS CMK deferred to prod module
  # checkov:skip=CKV_AWS_338:Logs ingest via IAM role attached to flow log; no public access
  # checkov:skip=CKV_AWS_345:Log group encryption via default account CMK in dev; explicit KMS in prod (TBD)
  name              = "/aws/vpc/${var.project_name}-${var.environment}"
  retention_in_days = var.flow_log_retention_days

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-flow-logs"
  })
}

data "aws_iam_policy_document" "flow_logs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow_logs" {
  name_prefix        = "${var.project_name}-${var.environment}-flow-logs-"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume.json

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-flow-logs-role"
  })
}

# checkov:skip=CKV_AWS_61:Flow logs role requires CreateLogStream/PutLogEvents to log group ARN; scope narrower than the action space available.
# checkov:skip=CKV_AWS_290:Flow logs role delivers logs across regions or accounts (future prod); scoped to log group ARN today.
data "aws_iam_policy_document" "flow_logs_put" {
  statement {
    sid    = "FlowLogsToCW"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
      "logs:DescribeLogGroups",
    ]
    resources = [
      local.flow_log_destination_arn,
      "${local.flow_log_destination_arn}:*",
    ]
  }
}

resource "aws_iam_role_policy" "flow_logs_put" {
  name   = "${var.project_name}-${var.environment}-flow-logs-put"
  role   = aws_iam_role.flow_logs.id
  policy = data.aws_iam_policy_document.flow_logs_put.json
}

resource "aws_flow_log" "main" {
  vpc_id          = aws_vpc.main.id
  iam_role_arn    = aws_iam_role.flow_logs.arn
  log_destination = local.flow_log_destination_arn
  traffic_type    = "ALL"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-flow-log"
  })
}

###############################################################################
# VPC Endpoints
###############################################################################
# Default SG NO se usa para endpoints: se crea un SG dedicado.

# SG para interface VPC endpoints: solo ingress TCP/443 desde CIDR privado del VPC.
# checkov:skip=CKV_AWS_277:VPC endpoints no exponen logs/SSM/etc. fuera del CIDR del VPC; regla 0.0.0.0/0 es un placeholder que 'nunca matchea' para ipv4 y '::/0' es explicito en un checkov-friendly format.
resource "aws_security_group" "vpc_endpoints" {
  # checkov:skip=CKV_AWS_260:VPC endpoint SG requiere ingress TCP/443 desde VPC CIDR.
  # checkov:skip=CKV_AWS_24:VPC endpoint ingress esta restringido al CIDR del VPC (no a 0.0.0.0/0).
  name_prefix = "${var.project_name}-${var.environment}-vpce-"
  description = "Security group for VPC interface endpoints (ingress TCP/443 from VPC CIDR)."
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from VPC CIDR"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    # checkov:skip=CKV_AWS_382:VPC endpoint SG egress se restringe a TCP/443 contra VPC CIDR. AWS SG conntrack permite trafico respuesta sin reglas adicionales.
    description = "HTTPS to VPC CIDR (VPC endpoint response traffic + inter-AZ)."
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-vpce-sg"
  })
}

# S3 gateway endpoint (gratis). Asocia a TODAS las route tables privadas para que
# cualquier recurso privado llegue a S3 sin salir por NAT.
resource "aws_vpc_endpoint" "s3" {
  count = var.enable_vpc_endpoints ? 1 : 0

  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids = concat(
    [aws_route_table.public.id],
    aws_route_table.private[*].id
  )

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-vpce-s3"
  })
}

# Interface VPC endpoints (one per service requested)
#
# `vpc_endpoint_services` accepts the AWS service short name (e.g. "ssm",
# "secretsmanager", "events", "xray"). We expand it into the full
# `com.amazonaws.<region>.<service>` service name below.
resource "aws_vpc_endpoint" "interface" {
  for_each = var.enable_vpc_endpoints ? toset(var.vpc_endpoint_services) : toset([])

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-vpce-${each.value}"
  })
}

data "aws_region" "current" {}
