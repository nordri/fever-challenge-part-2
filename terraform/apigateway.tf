resource "aws_api_gateway_rest_api" "events" {
  name        = "access-events"
  description = "Access event ingestion API"
}

resource "aws_api_gateway_resource" "events" {
  rest_api_id = aws_api_gateway_rest_api.events.id
  parent_id   = aws_api_gateway_rest_api.events.root_resource_id
  path_part   = "events"
}

resource "aws_api_gateway_method" "post_events" {
  rest_api_id   = aws_api_gateway_rest_api.events.id
  resource_id   = aws_api_gateway_resource.events.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "sqs" {
  rest_api_id = aws_api_gateway_rest_api.events.id
  resource_id = aws_api_gateway_resource.events.id
  http_method = aws_api_gateway_method.post_events.http_method

  type                    = "AWS"
  integration_http_method = "POST"

  uri = "arn:aws:apigateway:${var.aws_region}:sqs:path/000000000000/${aws_sqs_queue.events.name}"

  credentials = aws_iam_role.api_gateway.arn

  request_parameters = {
    "integration.request.header.Content-Type" = "'application/x-www-form-urlencoded'"
  }

  request_templates = {
    "application/json" = "Action=SendMessage&QueueUrl=$util.urlEncode(\"${aws_sqs_queue.events.url}\")&MessageBody=$util.urlEncode($input.body)"
  }

  passthrough_behavior = "NEVER"

  # Floci 1.5.34 applies these API Gateway integration settings but does not
# return them correctly on read-back, causing a perpetual Terraform diff.
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
  lifecycle {
  ignore_changes = [
    response_templates,
  ]
}
}

resource "aws_api_gateway_deployment" "events" {
  rest_api_id = aws_api_gateway_rest_api.events.id

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
