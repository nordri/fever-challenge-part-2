resource "aws_lambda_function" "processor" {
  function_name = "access-events-processor"
  role          = aws_iam_role.processor.arn

  runtime = "python3.12"
  handler = "handler.lambda_handler"

  filename         = "${path.module}/../lambda/build/lambda.zip"
  source_code_hash = filebase64sha256("${path.module}/../lambda/build/lambda.zip")

  timeout     = 10
  memory_size = 128

  environment {
    variables = {
      DYNAMODB_TABLE   = aws_dynamodb_table.events.name
      S3_BUCKET        = aws_s3_bucket.events.bucket
      AWS_ENDPOINT_URL = var.aws_endpoint_internal
    }
  }
}

resource "aws_lambda_event_source_mapping" "events" {
  event_source_arn = aws_sqs_queue.events.arn
  function_name    = aws_lambda_function.processor.arn

  batch_size = 1
  enabled    = true

  depends_on = [
    aws_iam_role_policy.processor_sqs
  ]
}
