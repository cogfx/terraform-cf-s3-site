variable "org" {
  type        = string
  description = "Organization acronym.  Will be used as resource prefix."
}

variable "environment" {
  type        = string
  description = "Target AWS Environment"
}

variable "domain_name" {
  type        = string
  description = ""
}