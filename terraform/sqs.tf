resource "aws_sqs_queue" "events_dlq" {
  name = "access-events-dlq"
}

resource "aws_sqs_queue" "events" {
  name = "access-events"

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.events_dlq.arn
    maxReceiveCount     = 3
  })
}
