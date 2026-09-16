terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "=5.100.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  endpoints {
    sqs            = var.aws_endpoint
    lambda         = var.aws_endpoint
    iam            = var.aws_endpoint
    dynamodb       = var.aws_endpoint
    s3             = var.aws_endpoint
    apigateway     = var.aws_endpoint
    secretsmanager = var.aws_endpoint
  }

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
}
