# Bucket names are globally unique. Because the stack is ephemeral and
# may be brought up/down rapidly, we suffix with a 6-char random hex so
# back-to-back cycles don't hit S3's "bucket name not yet released" error.
resource "random_id" "suffix" {
  byte_length = 3
}

resource "aws_s3_bucket" "this" {
  bucket = "${var.name_prefix}-frontend-${random_id.suffix.hex}"

  # Ephemeral: force_destroy lets `make down` delete a bucket that still has
  # the SPA bundle in it. Acceptable because the bundle is rebuilt from CI.
  force_destroy = true

  tags = {
    Name = "${var.name_prefix}-frontend-${random_id.suffix.hex}"
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  # Public website hosting requires these to be false.
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_website_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  index_document {
    suffix = var.index_document
  }

  error_document {
    key = var.error_document
  }
}

resource "aws_s3_bucket_policy" "public_read" {
  bucket = aws_s3_bucket.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicReadGetObject"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.this.arn}/*"
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.this]
}

resource "aws_s3_bucket_cors_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = ["*"]
    expose_headers  = []
    max_age_seconds = 3000
  }
}
