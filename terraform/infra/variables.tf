variable "region" {
  description = "AWS region for everything"
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Start of every resource name; keeps names unique in the shared account"
  type        = string
  default     = "evgenia-voting"
}

variable "vpc_cidr" {
  description = "Address range of the whole network"
  type        = string
  default     = "10.0.0.0/16"
}

variable "nat_zones" {
  description = "Zones that get a NAT gateway. [] = none (saves money), [\"a\", \"b\"] in step 3"
  type        = list(string)
  default     = ["a"]
}

variable "domain_name" {
  description = "My domain, bought at Porkbun"
  type        = string
  default     = "springlaughing.dev"
}