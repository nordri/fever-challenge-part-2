import json
import os
from datetime import datetime

import boto3
from botocore.exceptions import ClientError


dynamodb = boto3.resource("dynamodb")
s3 = boto3.client("s3")

table = dynamodb.Table(os.environ["DYNAMODB_TABLE"])
bucket = os.environ["S3_BUCKET"]


def lambda_handler(event, context):
    for record in event["Records"]:
        raw_payload = record["body"]
        payload = json.loads(raw_payload)

        event_id = payload["event_id"]
        timestamp = payload["timestamp"]

        event_datetime = datetime.fromisoformat(
            timestamp.replace("Z", "+00:00")
        )

        s3_key = f"events/{event_datetime:%Y/%m/%d}/{event_id}.json"

        try:
            table.put_item(
                Item={
                    "event_id": event_id,
                    "timestamp": timestamp,
                    "domain": payload["domain"],
                    "client_ip": payload["client_ip"],
                },
                ConditionExpression="attribute_not_exists(event_id)",
            )
        except ClientError as exc:
            if exc.response["Error"]["Code"] != "ConditionalCheckFailedException":
                raise

            print(json.dumps({
                "message": "Duplicate event detected",
                "event_id": event_id,
            }))

        s3.put_object(
            Bucket=bucket,
            Key=s3_key,
            Body=raw_payload.encode("utf-8"),
            ContentType="application/json",
        )

        print(json.dumps({
            "message": "Event processed",
            "event_id": event_id,
            "s3_key": s3_key,
        }))
