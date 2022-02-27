# Configure the default AWS Provider
provider "aws" {
  region = "ca-central-1"

  # skip_requesting_account_id should be disabled to generate valid ARN in apigatewayv2_api_execution_arn
  skip_requesting_account_id = false

  default_tags {
    tags = {
      environment = "dev"
    }
  }
}

# Configure additional AWS Provider
# CloudFront expects ACM resources in us-east-1 region only
provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"
}

resource "random_id" "this" {
  byte_length = 4
}

# Create S3 bucket (will be used as CloudFront origin)
module "s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 2.0"

  bucket = "s3-cc-${lower(random_id.this.id)}"
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

  #force_destroy = false # bucket contents will need to be addressed manually

  # tags = {
  #   environment = "dev"
  # }
}

output "id" {
  value = random_id.this.id
}
