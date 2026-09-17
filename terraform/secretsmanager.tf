resource "aws_secretsmanager_secret" "api_key" {
  name        = "access-events/api-key"
  description = "API key for the access events ingestion endpoint"

  recovery_window_in_days = 0
}
