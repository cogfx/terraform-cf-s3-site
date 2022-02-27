terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "= 3.74.2"
    }
  }  
}

# Configure the default AWS Provider
provider "aws" {
  region = "ca-central-1"

  # Make it faster by skipping something
  skip_get_ec2_platforms      = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  skip_credentials_validation = true

  # skip_requesting_account_id should be disabled to generate valid ARN in apigatewayv2_api_execution_arn
  skip_requesting_account_id = false
  
}

# Configure additional AWS Provider
# CloudFront expects ACM resources in us-east-1 region only
provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"
}

module "s3_one" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 2.0"

  bucket        = "s3-one-${random_pet.this.id}"
  force_destroy = true
}

resource "random_pet" "this" {
  length = 2
}