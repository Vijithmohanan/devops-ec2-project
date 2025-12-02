variable "aws_region" {
  description = "The AWS region"
  type        = string
  default     = "us-east-1" # Set a default to avoid prompting!
}

variable "key_pair_name" {
  description = "The name of the SSH keypair in AWS (must be created manually)"
  type        = string
}