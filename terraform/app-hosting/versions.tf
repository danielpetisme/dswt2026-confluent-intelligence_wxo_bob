terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    # For the IAM-propagation delay below -- same pattern the sibling
    # project uses for its own async-consistency workarounds.
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}
