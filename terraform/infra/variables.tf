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
  description = "Zones that get a NAT gateway. [] = none (saves money), [\"a\"] = one shared, [\"a\", \"b\"] = one per zone"
  type        = list(string)
  default     = ["a", "b"] #set to [] if want to remove NAT
}

variable "domain_name" {
  description = "My domain, bought at Porkbun"
  type        = string
  default     = "springlaughing.dev"
}

variable "instance_type" {
  description = "Size of every server"
  type        = string
  default     = "t3.micro"
}

# Which data server runs the primary database. Failover = change this to "c2".
variable "db_primary" {
  description = "Data server with the primary database: c1 (zone a) or c2 (zone b)"
  type        = string
  default     = "c1"

  validation {
    condition     = contains(["c1", "c2"], var.db_primary)
    error_message = "db_primary must be \"c1\" or \"c2\"."
  }
}

variable "alarm_email" {
  description = "Where alarm emails go (set in terraform.tfvars, not committed)"
  type        = string
}