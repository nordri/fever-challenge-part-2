# Terraform

This directory contains the Infrastructure as Code for the local cloud challenge.

Terraform provisions the AWS-style resources in **Floci 2.1.0**. The root `Makefile` is the recommended interface for deploying the complete challenge; the Makefile in this directory exposes Terraform-specific operations for development and inspection.

## Managed resources

Terraform provisions:

- SQS queue `access-events`;
- SQS Dead Letter Queue `access-events-dlq`;
- SQS redrive policy;
- DynamoDB table `access-events`;
- S3 bucket `access-events-raw`;
- Lambda processor and SQS event source mapping;
- IAM roles and least-privilege policies for Lambda and API Gateway;
- API Gateway REST API, `/events` resource and `POST` method;
- direct API Gateway → SQS integration;
- API Gateway deployment and `local` stage;
- API Gateway usage plan;
- Secrets Manager secret container for the API key.

The API Gateway ID is exported as a Terraform output and is used when starting the HTTPS proxy.

## Local provider configuration

The AWS provider targets Floci instead of a real AWS account.

Floci exposes its AWS-compatible APIs at:

```text
http://localhost:4566
```

Dummy AWS credentials are sufficient. When using the normal root-level workflow, the root `Makefile` supplies the required local environment automatically.

No AWS account is required.

## Usage

For a complete deployment, use the root Makefile:

```bash
make deploy
```

For Terraform-only operations from this directory:

```bash
make init
make validate
make plan
make apply
make destroy
```

Formatting can be checked/applied with:

```bash
make format
```

From the repository root, the Terraform plan can also be checked with:

```bash
make plan
```

A stable deployment should produce no infrastructure changes.

## API Gateway → SQS

API Gateway integrates directly with SQS rather than invoking an ingestion Lambda.

The `/events` `POST` method transforms the incoming request into an SQS `SendMessage` request and publishes it to the `access-events` queue.

The API Gateway IAM role is restricted to:

```text
sqs:SendMessage
```

on that queue.

## Lambda permissions

The Lambda processor IAM role is restricted to the operations required by the processing path:

```text
sqs:ReceiveMessage
sqs:DeleteMessage
sqs:GetQueueAttributes
dynamodb:PutItem
s3:PutObject
```

Each policy is scoped to its corresponding queue, table or bucket objects. Application policies do not use global `Action = "*"` or `Resource = "*"` permissions.

## Secrets Manager

Terraform manages the Secrets Manager **secret container**:

```text
access-events/api-key
```

The actual API-key value is deliberately not managed as a Terraform secret version.

This prevents the generated credential from being stored in Terraform state.

The root deployment calls `scripts/configure-api-key.sh`, which generates the value when necessary, stores it in Secrets Manager and configures the corresponding API Gateway API key and usage-plan association.

The script is idempotent and retrieves the value from Secrets Manager at runtime.

Because this is an ephemeral local environment, the secret is configured with an immediate deletion policy so a `destroy → deploy` cycle can reuse the same name without waiting for a recovery window.

## SQS and DLQ

The main queue is:

```text
access-events
```

Its Dead Letter Queue is:

```text
access-events-dlq
```

The redrive policy uses:

```text
maxReceiveCount = 3
```

Messages that repeatedly fail processing can therefore leave the main queue instead of being retried indefinitely.

## Persistence

The processor writes structured events to DynamoDB:

```text
access-events
```

with `event_id` as the partition key.

Raw payloads are written to:

```text
s3://access-events-raw/events/YYYY/MM/DD/<event_id>.json
```

The deterministic identities are part of the idempotency strategy used by the Lambda processor.

## Generated Lambda package

Terraform deploys:

```text
../lambda/build/lambda.zip
```

The ZIP is generated from source and dependencies by the Lambda Makefile and is not versioned.

The root deployment builds it before Terraform runs.

Terraform uses the ZIP hash so changes to the generated function package are detected during planning.

## Cleanup

Runtime events create objects in the S3 bucket.

The root `make destroy` workflow empties generated S3 data before invoking Terraform destroy so the bucket can be removed cleanly in the local emulator.

For that reason, the recommended full lifecycle operation is:

```bash
make destroy
```

from the repository root rather than invoking Terraform directly when the stack contains runtime data.

## State and evidence

Terraform state is local and is not committed to Git.

The evidence collector records useful Terraform information in `dump-cloud/`, including:

```text
terraform-state-list.txt
terraform-state-show.txt
```

These files are generated artifacts rather than source files.

The API-key value is not stored in Terraform state.
