locals {
  domain_name  = trimsuffix(var.domain_name, ".")
  s3_origin_id = lower(random_id.oai.hex)
  thistags  = {
    terraform-uid     = lower(random_id.this.hex)
    terraform-updated = timestamp()
    environment       = var.environment
  }
}

# Configure the default AWS Provider
provider "aws" {
  region = "ca-central-1"

  # skip_requesting_account_id should be disabled to generate valid ARN in apigatewayv2_api_execution_arn
  skip_requesting_account_id = false

  default_tags {
    tags = {
      terraform-uid     = lower(random_id.this.hex)
      terraform-updated = timestamp()
      environment       = var.environment
    }
  }
}

# Configure additional AWS Provider - CloudFront expects ACM resources in us-east-1 region only
provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"

  default_tags {
    tags = {
      terraform-uid     = lower(random_id.this.hex)
      terraform-updated = timestamp()
      environment       = var.environment
    }
  }
}

resource "random_id" "this" {
  byte_length = 4
}

resource "random_id" "oai" {
  byte_length = 8
}

### S3 bucket - CloudFront origin content
module "s3_bucket_content" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 2.0"

  bucket = "${lower(var.org)}-cc-${lower(var.environment)}-cloudfront-content-${lower(random_id.this.hex)}"
  #acl    = "private"

  # organization SCP blocks public S3 buckets
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true


  # organization policy -> all S3 buckets must be encrypted using KMS
  # encrupt using AWS managed S3 key for compatibility with AWS CloudFront
  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }
}

### S3 bucket - CloudFront origin content
module "s3_bucket_logs" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 2.0"

  bucket = "${lower(var.org)}-cc-${lower(var.environment)}-cloudfront-logs-${lower(random_id.this.hex)}"
  #acl    = "private"

  # organization SCP blocks public S3 buckets
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true


  # organization policy -> all S3 buckets must be encrypted using KMS
  # encrupt using AWS managed S3 key for compatibility with AWS CloudFront
  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }
}

### Create TLS Certificate (AWS Certificate Manager)
resource "aws_acm_certificate" "tls" {
  provider          = aws.us-east-1
  domain_name       = local.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

output "example" {
  value       = aws_acm_certificate.tls.domain_validation_options
}


### Create CloudFront Distribution
resource "aws_cloudfront_origin_access_identity" "oai" {
  comment = "OAI-${local.s3_origin_id}" # Sets OAI 'Name' value
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = module.s3_bucket_content.s3_bucket_bucket_domain_name
    origin_id   = local.s3_origin_id

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.oai.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${local.domain_name}" # Sets distribtion 'Description' value
  default_root_object = "index.html"

  logging_config {
    include_cookies = false
    bucket          = module.s3_bucket_logs.s3_bucket_bucket_domain_name
    prefix          = "myprefix"
  }

  aliases = ["${local.domain_name}"]

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  # Cache behavior with precedence 0
  ordered_cache_behavior {
    path_pattern     = "/content/immutable/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false
      headers      = ["Origin"]

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  # Cache behavior with precedence 1
  ordered_cache_behavior {
    path_pattern     = "/content/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  price_class = "PriceClass_100"

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["US", "CA", "GB", "DE"]
    }
  }

  # tags = {
  #   Environment = "production"
  # }

  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.tls.arn
    ssl_support_method  = "sni-only"
  }
}


### OAI - Data - IAM Policy - allow CF dist access S3 bucket
data "aws_iam_policy_document" "s3_bucket_content" {
  statement {
    sid = "AllowCloudFrontListBucket"
    actions = [
      "s3:ListBucket"
    ]
    effect = "Allow"
    principals {
      type = "AWS"
      identifiers = [
        "${aws_cloudfront_origin_access_identity.oai.iam_arn}"
      ]
    }
    resources = [
      module.s3_bucket_content.s3_bucket_arn
    ]
  }
  statement {
    sid = "AllowCloudFrontGetObject"
    actions = [
      "s3:GetObject"
    ]
    effect = "Allow"
    principals {
      type = "AWS"
      identifiers = [
        "${aws_cloudfront_origin_access_identity.oai.iam_arn}"
      ]
    }
    resources = [
      format("%s/*", module.s3_bucket_content.s3_bucket_arn)
    ]
  }
}


resource "aws_s3_bucket_policy" "bucket_policy" {
  bucket = module.s3_bucket_content.s3_bucket_id
  policy = data.aws_iam_policy_document.s3_bucket_content.json
}

### OAI - Resource - S3 Bucket Policy - connect IAM policy to S3 bucket

### Create Route53 DNS entry

### Data Create ACM - done manually