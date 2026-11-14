variable "aws_region" {
  description = "Learner Lab : us-east-1 ou us-west-2 uniquement."
  type        = string
  default     = "us-east-1"
}

variable "ecr_repository" {
  type    = string
  default = "devsecops-demo"
}
