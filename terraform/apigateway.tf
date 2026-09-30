resource "aws_api_gateway_rest_api" "events" {
  name        = "access-events"
  description = "Access event ingestion API"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "events" {
  rest_api_id = aws_api_gateway_rest_api.events.id
  parent_id   = aws_api_gateway_rest_api.events.root_resource_id
  path_part   = "events"
}

resource "aws_api_gateway_model" "event" {
  rest_api_id  = aws_api_gateway_rest_api.events.id
  name         = "AccessEvent"
  content_type = "application/json"
  schema       = jsonencode(local.event_schema)
}

resource "aws_api_gateway_request_validator" "event" {
  rest_api_id                 = aws_api_gateway_rest_api.events.id
  name                        = "validate-event-body"
  validate_request_body       = true
  validate_request_parameters = false
}

resource "aws_api_gateway_method" "post_events" {
  rest_api_id   = aws_api_gateway_rest_api.events.id
  resource_id   = aws_api_gateway_resource.events.id
  http_method   = "POST"
  authorization = "NONE"

  api_key_required     = true
  request_validator_id = aws_api_gateway_request_validator.event.id
  request_models = {
    "application/json" = aws_api_gateway_model.event.name
  }
}

resource "aws_api_gateway_integration" "sqs" {
  rest_api_id = aws_api_gateway_rest_api.events.id
  resource_id = aws_api_gateway_resource.events.id
  http_method = aws_api_gateway_method.post_events.http_method

  type                    = "AWS"
  integration_http_method = "POST"

  uri         = "arn:aws:apigateway:${var.aws_region}:sqs:path/000000000000/${aws_sqs_queue.events.name}"
  credentials = aws_iam_role.api_gateway.arn

  request_parameters = {
    "integration.request.header.Content-Type" = "'application/x-www-form-urlencoded'"
  }

  # Floci 1.5.34 requires QueueUrl explicitly for the SQS SendMessage
  # integration. Terraform injects the provisioned queue URL here.
  request_templates = {
    "application/json" = "Action=SendMessage&QueueUrl=$util.urlEncode(\"${aws_sqs_queue.events.url}\")&MessageBody=$util.urlEncode($input.body)"
  }

  passthrough_behavior = "NEVER"

  # Floci applies these attributes correctly but does not return them
  # consistently through GetIntegration, which otherwise causes
  # perpetual Terraform diffs.
  lifecycle {
    ignore_changes = [
      credentials,
      request_parameters,
      request_templates,
      timeout_milliseconds,
    ]
  }
}

resource "aws_api_gateway_method_response" "accepted" {
  rest_api_id = aws_api_gateway_rest_api.events.id
  resource_id = aws_api_gateway_resource.events.id
  http_method = aws_api_gateway_method.post_events.http_method
  status_code = "202"
}

resource "aws_api_gateway_integration_response" "accepted" {
  rest_api_id = aws_api_gateway_rest_api.events.id
  resource_id = aws_api_gateway_resource.events.id
  http_method = aws_api_gateway_method.post_events.http_method
  status_code = aws_api_gateway_method_response.accepted.status_code

  response_templates = {
    "application/json" = jsonencode({
      status = "accepted"
    })
  }

  depends_on = [
    aws_api_gateway_integration.sqs
  ]

  # Same Floci read-back limitation as the integration above.
  lifecycle {
    ignore_changes = [
      response_templates,
    ]
  }
}

# Use declared configuration rather than provider-computed IDs so the
# deployment trigger remains stable during terraform apply.
locals {
  event_schema = {
    "$schema" = "http://json-schema.org/draft-04/schema#"
    type      = "object"
    required  = ["event_id", "timestamp", "domain", "client_ip"]
    properties = {
      event_id  = { type = "string", minLength = 1 }
      timestamp = { type = "string", minLength = 1 }
      domain    = { type = "string", minLength = 1 }
      client_ip = { type = "string", minLength = 1 }
    }
  }

  api_deployment_config = {
    resource_path    = "events"
    http_method      = "POST"
    api_key_required = true
    integration_type = "AWS"
    queue_name       = aws_sqs_queue.events.name
    event_schema     = local.event_schema
    request_validation = {
      body       = aws_api_gateway_request_validator.event.validate_request_body
      parameters = aws_api_gateway_request_validator.event.validate_request_parameters
      models     = aws_api_gateway_method.post_events.request_models
    }
  }
}

resource "aws_api_gateway_deployment" "events" {
  rest_api_id = aws_api_gateway_rest_api.events.id

  triggers = {
    redeployment = sha1(jsonencode(local.api_deployment_config))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.sqs,
    aws_api_gateway_integration_response.accepted
  ]
}

resource "aws_api_gateway_stage" "events" {
  deployment_id = aws_api_gateway_deployment.events.id
  rest_api_id   = aws_api_gateway_rest_api.events.id
  stage_name    = "local"
}

resource "aws_api_gateway_usage_plan" "events" {
  name = "access-events"
  api_stages {
    api_id = aws_api_gateway_rest_api.events.id
    stage  = aws_api_gateway_stage.events.stage_name
  }
}
