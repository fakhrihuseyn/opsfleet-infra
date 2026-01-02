variable "region" {
  type    = string
  default = "eu-west-1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.100.0.0/16"
}

variable "cluster_name" {
  type    = string
  default = "opsfleetstech"
}

variable "env_name" {
  description = "Environment suffix to append to cluster name (e.g. dev, prod). Empty means no suffix."
  type        = string
  default     = ""
}

variable "amd64_instance_types" {
  description = "List of instance types to use for the amd64 node group"
  type        = list(string)
  default     = ["t3.small", "t3.medium"]
}
variable "arm64_instance_types" {
  description = "List of instance types to use for the arm64 node group"
  type        = list(string)
  default     = ["m6g.medium", "m6g.large"]
}
variable "desired_capacity" {
  type    = number
  default = 2
}

variable "common_tags" {
  description = "Common tags to apply to resources (merged with resource-specific tags)"
  type        = map(string)
  default     = {}
}
