variable "gcp_project_id" {
  description = "The ID of the Google Cloud project."
  type        = string
}

variable "gcp_region" {
  description = "The Google Cloud region to create resources in."
  type        = string
  default     = "us-central1"
}

variable "gcp_zone" {
  description = "The GCP zone to deploy the VM into."
  type        = string
  default     = "us-central1-a"
}