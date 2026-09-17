output "api_gateway_id" {
  description = "API Gateway REST API identifier"
  value       = aws_api_gateway_rest_api.events.id
}

