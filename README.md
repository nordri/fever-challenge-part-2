# Fever Systems Hiring Challenge — Local Cloud

This repository contains the **local cloud (IaC + Serverless)** part of the Fever Systems hiring challenge.

The solution provisions and exercises a fully local, event-driven AWS-style architecture using **Floci 2.1.0** and **Terraform**. It requires no AWS account, no cloud resources and no paid services.

The main interface for the reviewer is intentionally small:

```bash
make deploy
make test
make evidence
make destroy
```

`make deploy` is idempotent and builds the complete environment from source.

---

## Architecture

```text
                         HTTPS
                           │
                           ▼
                    ┌─────────────┐
                    │    Nginx    │
                    │ TLS proxy   │
                    └──────┬──────┘
                           │
                           ▼
                    ┌─────────────┐
                    │ API Gateway │
                    │   REST API  │
                    │   API key   │
                    └──────┬──────┘
                           │
                      SendMessage
                           │
                           ▼
                    ┌─────────────┐
                    │     SQS     │──────────────► DLQ
                    │access-events│
                    └──────┬──────┘
                           │
                    Event Source Mapping
                           │
                           ▼
                    ┌─────────────┐
                    │   Lambda    │
                    │  processor  │
                    └──────┬──────┘
                           │
                    ┌──────┴──────┐
                    │             │
                    ▼             ▼
              ┌──────────┐   ┌──────────┐
              │ DynamoDB │   │    S3    │
              │structured│   │   raw    │
              │  events  │   │ payloads │
              └──────────┘   └──────────┘
```

The client connects to an Nginx HTTPS endpoint using a locally generated trusted CA. Nginx terminates TLS and forwards the request to the REST API in Floci.

API Gateway performs API-key authentication and integrates **directly with SQS**. There is no ingestion Lambda between API Gateway and the queue.

SQS decouples ingestion from processing. A Lambda event source mapping consumes messages from the queue. Failed messages are retried and are eventually moved to a Dead Letter Queue (DLQ) according to the queue redrive policy.

The processor stores:

- a structured representation of the event in DynamoDB;
- the raw payload in S3 under `events/YYYY/MM/DD/<event_id>.json`.

---

## Project structure

```text
.
├── docker-compose.yml
├── Makefile
├── terraform/          # Infrastructure as Code
├── lambda/             # Lambda source and reproducible ZIP build
├── proxy/              # Nginx TLS proxy configuration
├── scripts/            # Bootstrap, tests, cleanup and evidence collection
├── dump-cloud/         # Generated cloud-state evidence
└── logs/               # Generated execution evidence
```

`dump-cloud/`, `logs/`, generated certificates and Lambda build artifacts are runtime/generated artifacts and are intentionally not versioned.

They can be regenerated using the provided automation. Evidence directories may nevertheless be present in the submitted challenge archive so the captured execution can be reviewed without rerunning the stack.

---

## Prerequisites

The challenge is designed to run entirely on the local machine.

Required tools:

- Docker
- Docker Compose
- Terraform
- AWS CLI
- GNU Make
- Python 3 / `pip`
- `zip`
- OpenSSL
- `curl`

No AWS account or real AWS credentials are required.

Floci is pinned to:

```text
floci/floci:2.1.0
```

The root Makefile provides the dummy AWS credentials and local endpoint configuration required by Floci, so the reviewer does not need to export them manually.

---

## Quick start

From the repository root:

```bash
make deploy
```

This performs the complete bootstrap:

1. starts Floci;
2. waits until its API is ready;
3. generates the local CA and TLS certificate when required;
4. builds the Lambda deployment ZIP including its dependencies;
5. initializes Terraform;
6. provisions the infrastructure;
7. creates/configures the API key using Secrets Manager;
8. starts the HTTPS Nginx proxy using the API Gateway ID created by Terraform.

After deployment, the endpoint is:

```text
https://localhost:8443/events
```

The generated local CA is:

```text
proxy/certs/ca.crt
```

A second `make deploy` can be run against the existing environment. The deployment is designed to be idempotent.

---

## Testing

Run:

```bash
make test
```

The automated test performs an end-to-end verification of the deployed system.

Before accepting the valid event, it sends authenticated requests containing
malformed JSON, missing required fields, an incorrect field type, and a JSON
array. Each must return HTTP `400`. A malformed JSON request with
`Content-Type: application/json; charset=utf-8` also checks the default model.
These checks fail if the emulator accepts an invalid body.

The API Gateway request validator uses a JSON Schema model requiring an object
with non-empty string fields `event_id`, `timestamp`, `domain`, and `client_ip`.
This validates structure; it does not validate timestamp, domain, or IP semantics.
The model is attached through `$default` so content-type variations do not skip
body validation. Changes to the schema or validation configuration trigger a new
API deployment.

It checks:

1. an HTTPS request **without** an API key is rejected with HTTP `403`;
2. an authenticated HTTPS request is accepted with HTTP `202`;
3. the event is asynchronously processed;
4. the structured event appears in DynamoDB;
5. the raw event appears in S3;
6. the same authenticated event is sent again;
7. only one DynamoDB record and one S3 object exist for that `event_id`.

A new `event_id` is generated for each execution of the test. Within the same test execution, the authenticated payload is deliberately submitted twice to verify idempotency.

Example output:

```text
==> Retrieving API key from Secrets Manager
==> Testing request without API key
    Authentication rejected correctly: HTTP 403
==> Testing authenticated HTTPS request
    Event accepted: HTTP 202
==> Waiting for event processing
    DynamoDB record found
    S3 object found
==> Testing idempotency
    DynamoDB records: 1
    S3 objects:       1

All tests passed
Event ID: test-<timestamp>
```

The test also writes the HTTP evidence to:

```text
logs/https-request-response.txt
```

The API-key value is never written to the evidence file.

---

## HTTPS and local certificate trust

The public challenge endpoint uses real TLS termination through Nginx.

A small local Certificate Authority and a server certificate for `localhost` are generated by:

```text
scripts/generate-certs.sh
```

The server certificate includes `localhost` as a Subject Alternative Name.

Clients validate the certificate using the generated CA:

```bash
curl \
  --cacert proxy/certs/ca.crt \
  https://localhost:8443/events
```

TLS verification is **not disabled**. The solution does not use `curl -k` / `--insecure`.

The CA only exists for this local challenge environment and does not need to be installed in the operating-system trust store.

---

## API authentication and secret management

The REST API requires an API key.

Terraform provisions:

- the Secrets Manager secret container;
- the API Gateway usage plan and associated infrastructure.

The actual API-key value is intentionally **not created as a Terraform-managed secret value**. This avoids storing the credential in Terraform state.

`scripts/configure-api-key.sh` performs the runtime configuration:

1. reads the secret from Secrets Manager;
2. generates a random value if no value exists;
3. stores it in Secrets Manager;
4. creates/reuses the API Gateway API key;
5. associates it with the usage plan.

The script is idempotent and does not print the secret value.

Runtime clients, including the automated test, retrieve the value from Secrets Manager when it is required.

The generated evidence contains secret metadata where useful, but never the secret value.

---

## Event format

The automated test sends events with the following structure:

```json
{
  "event_id": "test-<timestamp>",
  "timestamp": "2026-09-17T07:39:12Z",
  "domain": "automated-test.local",
  "client_ip": "192.0.2.100"
}
```

`event_id` is the stable identity used by the processor for idempotency.

---

## Asynchronous processing

API Gateway sends accepted requests directly to the `access-events` SQS queue.

This deliberately avoids an unnecessary synchronous ingestion Lambda:

```text
API Gateway → SQS → Lambda
```

The Lambda processor is attached to SQS through an event source mapping.

This keeps ingestion and processing decoupled and allows SQS to handle retries when processing fails.

---

## Dead Letter Queue

The main SQS queue has a redrive policy pointing to:

```text
access-events-dlq
```

The configured maximum receive count is `3`.

A message that repeatedly fails processing is therefore moved out of the main queue instead of being retried indefinitely.

The queue and DLQ attributes are included in the generated cloud evidence.

---

## Idempotency

SQS provides at-least-once delivery semantics, so the processor must tolerate receiving the same logical event more than once.

The solution uses `event_id` as the stable event identity.

DynamoDB uses `event_id` as its key and the Lambda performs a conditional write so that an already processed event does not create another record.

S3 uses a deterministic object key:

```text
events/YYYY/MM/DD/<event_id>.json
```

As a result, retrying or resubmitting the same event does not create additional DynamoDB records or additional S3 object keys.

`make test` explicitly exercises this behaviour by submitting the same authenticated payload twice and verifying the final persisted state.

---

## IAM and least privilege

Separate IAM roles are used for the components that need AWS API access.

### Lambda processor

The processor role is limited to:

```text
sqs:ReceiveMessage
sqs:DeleteMessage
sqs:GetQueueAttributes
```

on the event queue;

```text
dynamodb:PutItem
```

on the event table; and

```text
s3:PutObject
```

on objects in the raw-event bucket.

### API Gateway

The API Gateway role is limited to:

```text
sqs:SendMessage
```

on the event queue.

The application policies do not use global `Action = "*"` or `Resource = "*"` permissions.

---

## Evidence

After a successful deployment and test, run:

```bash
make evidence
```

The evidence collector creates a compact snapshot of the deployed environment.

### `dump-cloud/`

The generated files include Terraform and AWS-style state such as:

- Terraform state resource list;
- Terraform state details;
- DynamoDB contents;
- recursive S3 object listing;
- main SQS queue attributes;
- DLQ attributes;
- Lambda configuration;
- Lambda event source mappings;
- API Gateway metadata;
- Secrets Manager metadata.

### `logs/`

Execution evidence includes:

- the authenticated and unauthenticated HTTPS request/response evidence;
- Lambda execution logs.

The HTTP evidence identifies the test `event_id`, making it possible to correlate the accepted request with the persisted data and Lambda execution.

Sensitive secret values are deliberately excluded from evidence.

---

## Terraform

Terraform is responsible for the infrastructure lifecycle, including:

- SQS queue and DLQ;
- DynamoDB table;
- S3 bucket;
- Lambda function;
- Lambda event source mapping;
- IAM roles and policies;
- API Gateway REST API and SQS integration;
- API Gateway deployment/stage;
- usage plan;
- Secrets Manager secret container.

Terraform-specific commands are available through the Makefile in `terraform/`, while the root Makefile is the intended reviewer interface.

To verify that the current deployment matches the configuration:

```bash
make plan
```

A stable deployment should report no infrastructure changes.

---

## Lambda packaging

The Lambda function is packaged as a ZIP and does not use Lambda Layers.

The build is reproducible from:

```text
lambda/src/
```

and:

```text
lambda/src/requirements.txt
```

The Lambda Makefile installs the pinned Python dependencies into a temporary package directory, copies the handler and creates:

```text
lambda/build/lambda.zip
```

The ZIP is a generated artifact and is not versioned.

---

## Cleanup

Destroy the environment with:

```bash
make destroy
```

The cleanup automation removes runtime S3 objects before Terraform destroys the infrastructure. This is required because an S3 bucket containing generated event data cannot be removed while it is non-empty.

Secrets Manager is configured for immediate deletion in this ephemeral local environment, allowing a complete:

```text
deploy → test → destroy → deploy
```

cycle without leaving a secret name pending deletion.

Finally, Docker Compose removes the local services.

---

## Useful commands

The normal reviewer workflow is:

```bash
make deploy
make test
make evidence
make plan
make destroy
```

Individual lifecycle targets are also available for development/debugging, but are not required for the normal challenge execution.

---

## Design decisions

### Direct API Gateway → SQS integration

API Gateway publishes directly to SQS rather than invoking an ingestion Lambda.

This reduces the number of moving parts and keeps the synchronous request path small.

### Local TLS proxy

Floci provides the AWS-compatible local APIs, while Nginx provides the externally visible HTTPS endpoint.

The API Gateway ID is only known after Terraform creates the REST API, so the proxy is started after infrastructure provisioning and receives that ID dynamically.

### Secret value outside Terraform state

Terraform owns the secret resource, but not the API-key value.

The value is generated and stored by an idempotent runtime script so the credential is not persisted in Terraform state.

### Deterministic persistence

The event ID is used as the DynamoDB identity and as part of the deterministic S3 object key. This makes duplicate delivery observable but harmless with respect to duplicate persisted records/objects.

### Automation over manual setup

The scripts contain operational/control-flow logic while the Makefiles remain small orchestration interfaces. The reviewer should not need to manually discover resource IDs, configure credentials or copy generated values between commands.

---

## Floci scope

This solution intentionally targets the local environment requested by the challenge and is tested with **Floci 2.1.0**.

Floci exposes AWS-compatible APIs locally at:

```text
http://localhost:4566
```

The implementation is designed to satisfy and demonstrate the challenge requirements locally. It is not presented as a drop-in production deployment for a real AWS account.

---

## End-to-end workflow

For a clean review of the solution:

```bash
make deploy
make test
make evidence
make plan
make destroy
```

Expected result:

```text
deployment      → complete
authentication  → 403 without key / 202 with key
processing      → event consumed asynchronously
DynamoDB        → event persisted
S3              → raw payload persisted
idempotency     → one record / one object
evidence        → generated
Terraform plan  → no changes
cleanup         → complete
```
