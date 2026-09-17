resource "aws_s3_bucket" "events" {
  bucket        = "access-events-raw"
  force_destroy = true
}
