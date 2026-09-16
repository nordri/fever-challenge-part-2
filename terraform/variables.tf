variable "aws_region" {
  description = "AWS region used by the local Floci environment"
  type        = string
  default     = "eu-west-1"
}

variable "aws_endpoint" {
  description = "Floci AWS API endpoint"
  type        = string
  default     = "http://localhost:4566"
}

variable "aws_endpoint_internal" {
  description = "Floci endpoint reachable from Lambda containers"
  type        = string
  default     = "http://floci:4566"
}
