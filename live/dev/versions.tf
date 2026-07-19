terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.55"
    }
  }

  backend "s3" {
    # Valores reales via backend-config al hacer init.
    # Ver scripts/bootstrap-backend.sh.
    # bucket       = "orion-tfstate-dev"
    # key          = "dev/terraform.tfstate"
    # region       = "us-east-1"
    # use_lockfile = true
    # encrypt      = true
  }
}