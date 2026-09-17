# Bonus considerations

The core challenge intentionally focuses on the required end-to-end path and keeps the solution small, reproducible and easy to review.

The optional bonuses below were considered during the design. They were not implemented because each introduces additional infrastructure or integration scope without being necessary to demonstrate the core requirements. This document describes how I would approach them and the trade-offs behind leaving them out.

## 1. Remote Terraform state

> Remote Terraform state stored in an S3 bucket on Floci, with a DynamoDB lock table.

An S3 backend is a standard approach for shared Terraform state. In a collaborative environment I would avoid keeping state only on an engineer's workstation and use a remotely accessible backend with locking.

A modern S3 backend would conceptually look like:

```hcl
terraform {
  backend "s3" {
    key                  = "terraform.tfstate"
    workspace_key_prefix = "access-events"
    encrypt              = true
    use_lockfile         = true
  }
}
```

Backend-specific values such as bucket, region and the Floci endpoint can be supplied during `terraform init` rather than hardcoded.

### DynamoDB locking

The bonus explicitly asks for a DynamoDB lock table. That was historically the standard Terraform S3-backend locking mechanism, but DynamoDB-based locking is now deprecated by Terraform in favour of S3 native state locking with `use_lockfile = true`.

If implementing the bonus literally, I would provision the DynamoDB lock table and configure the backend accordingly to satisfy the exercise. For a new real-world implementation, I would prefer S3 native locking unless compatibility requirements required the older mechanism.

### Bootstrap problem

Terraform cannot use an S3 backend until the backend bucket already exists. The backend therefore cannot simply be provisioned by the same Terraform state that depends on it.

A clean implementation would introduce a small bootstrap stage:

```text
bootstrap Terraform
        │
        ├── S3 state bucket
        └── DynamoDB lock table (if required)
                │
                ▼
        terraform init
                │
                ▼
        application Terraform
```

The bootstrap state would remain separate from the application state.

For this local challenge that adds a second Terraform lifecycle solely to move a state file from the local filesystem into another local service running in the same Floci instance. The core solution is single-user, ephemeral and reproducible, so I chose to keep local Terraform state rather than introduce that extra bootstrap layer.

## 2. Step Functions orchestration

> Orchestrate the processing with Step Functions (a state machine with `Retry` / `Catch` error handling) instead of a direct queue-to-Lambda integration.

The current processing path is deliberately simple:

```text
API Gateway → SQS → Lambda → DynamoDB / S3
```

SQS already provides asynchronous decoupling and redelivery, while the DLQ provides a terminal path for repeatedly failing messages.

A Step Functions implementation would insert an explicit state machine into the processing workflow and model failure behaviour with `Retry` and `Catch`:

```text
SQS
 │
 ▼
Step Functions
 │
 ├── Invoke processor
 │       ├── Retry transient failures
 │       └── Catch terminal failures
 ├── Success path
 └── Failure path
```

This becomes useful when processing is genuinely a workflow: multiple steps must be coordinated, different failure classes require different handling, state must be preserved between stages, or execution history is operationally valuable.

For this challenge there is only one small processing unit. Introducing a state machine would add resources, IAM relationships and another retry/failure layer without simplifying the required behaviour.

I therefore kept the direct SQS-to-Lambda event source mapping. If the processing flow grew into several independently retryable operations, Step Functions would become a stronger design option.

## 3. ACM certificate modelled in Terraform

> Declare an ACM certificate via Terraform as part of your IaC. Floci implements the ACM control plane. It will not terminate real TLS — that stays with the proxy.

This bonus is primarily about modelling the certificate resource in IaC rather than changing the actual TLS data path.

The current architecture is:

```text
client
  │ HTTPS
  ▼
Nginx
  │ TLS termination
  ▼
Floci / API Gateway
```

Because Floci only implements the ACM control plane for this purpose, declaring an ACM certificate would not replace the local CA and server certificate used by Nginx.

A certificate could be modelled in Terraform along these lines:

```hcl
resource "aws_acm_certificate" "api" {
  domain_name       = "localhost"
  validation_method = "DNS"
}
```

Subject to the exact ACM behaviour exposed by Floci, its ARN could then be exported or referenced by the modelled infrastructure where appropriate.

The important distinction is that there would be two separate concerns:

```text
ACM resource
    └── infrastructure/control-plane model

Local CA + Nginx certificate
    └── actual TLS termination and certificate validation
```

The Nginx certificate would still be required because the client must perform real TLS validation and the Floci ACM resource does not terminate the HTTPS connection.

I chose not to add an ACM resource merely as a control-plane object when it does not participate in the functional request path. The current implementation instead demonstrates TLS end to end: HTTPS is real, the hostname is validated, and the client does not disable certificate verification.

## 4. Kubernetes access-log integration

> Wire it to the cluster: make the `server.py` from the Kubernetes challenge ship its access logs to your endpoint.

This would connect both parts of the technical challenge:

```text
Kubernetes server.py
        │ access event
        ▼
https://localhost:8443/events
        │
        ▼
API Gateway → SQS → Lambda
                       ├── DynamoDB
                       └── S3
```

At application level the change is straightforward: `server.py` would emit an event matching the local-cloud API contract and authenticate using the API key.

The more interesting problem is the environment boundary. The Kubernetes challenge runs in KillerKoda, while the cloud stack runs locally in Docker. A complete integration would need to address:

- how the Kubernetes workload reaches the local HTTPS endpoint;
- how the local CA is provided to the workload so TLS remains verified;
- how the API key is injected without hardcoding or committing it;
- retry/failure behaviour when the event endpoint is unavailable;
- ensuring the integration does not regress the behaviour required by the Kubernetes challenge.

If both workloads shared a networking and secret-management environment, the application integration would be relatively small. Recreating and coupling the KillerKoda environment solely for this bonus introduces a separate networking and environment exercise around two already working challenge solutions.

For that reason I kept both challenge parts independently reproducible rather than coupling them only for the bonus.

## Summary

| Bonus | What it demonstrates | Main additional cost |
| --- | --- | --- |
| Remote state | Shared state and state locking | Backend bootstrap and second Terraform lifecycle |
| Step Functions | Explicit workflow orchestration | Additional states, IAM and retry/failure semantics |
| ACM | Certificate modelling in IaC | Control-plane resource that does not provide the real TLS path |
| Kubernetes integration | End-to-end integration between both challenges | Cross-environment networking, CA and secret distribution |

The submitted implementation prioritises the required path:

```text
HTTPS → authentication → API Gateway → SQS → Lambda → DynamoDB/S3
```

together with least-privilege IAM, DLQ handling, idempotency, automated deployment, automated verification and captured evidence.

The bonuses were deliberately left as design considerations rather than adding infrastructure that was not required by the functional solution.
