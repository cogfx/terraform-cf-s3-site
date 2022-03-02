# Configure the default AWS Provider
provider "aws" {
  region = "ca-central-1"

  # skip_requesting_account_id should be disabled to generate valid ARN in apigatewayv2_api_execution_arn
  skip_requesting_account_id = false

  default_tags {
    tags = {
      terraform-uid = lower(random_id.this.hex)
      terraform-updated = timestamp()
      environment = var.environment
    }
  }
}

# Configure additional AWS Provider
# CloudFront expects ACM resources in us-east-1 region only
provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"
}

locals {
  domain_name = trimsuffix(var.domain_name, ".")
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
  acl    = "private"

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
  acl    = "private"

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

# ### Create TLS Certificate (AWS Certificate Manager)
# resource "aws_acm_certificate" "this" {
#   provider          = aws.us-east-1
#   domain_name       = local.domain_name
#   validation_method = "DNS"

#   lifecycle {
#     create_before_destroy = true
#   }
# }

# # ### Create CloudFront Distribution
# # module "cdn" {
# #   source = "terraform-aws-modules/cloudfront/aws"

# #   aliases = ["${local.domain_name}"]

# #   comment             = "${var.org} - S3 - (${var.environment})"
# #   enabled             = true
# #   is_ipv6_enabled     = true
# #   price_class         = "PriceClass_100"
# #   retain_on_delete    = false
# #   wait_for_deployment = false

# #   create_origin_access_identity = true
# #   origin_access_identities = {
# #     s3_bucket_one = "lower(${random_id.oai.hex})"
# #   }



# }


### OAI - Data - IAM Policy - allow CF dist access S3 bucket

### OAI - Resource - S3 Bucket Policy - connect IAM policy to S3 bucket

### Create Route53 DNS entry

### Data Create ACM - done manually