/**
 * Copyright 2018 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

variable "project_id" {
  description = "GCP Project to deploy resources"
}

variable "organization_id" {
  description = "Parent Organization ID for the project"
}

variable "folder_id" {
  description = "Folder ID for the project. Leave blank for Org top level project"
  default = ""
}

variable "billing_account" {
  description = "Billing Account for the project. Leave blank for default"
  default = ""
}


variable "kubernetes_cluster_name" {
  description = "Name or the GKE cluster"
  default = "services"
}
variable "domain" {
  description = "Domain for hosting gitlab functionality (ie mydomain.com would access gitlab at gitlab.mydomain.com)"
  default     = ""
}

variable "certmanager_email" {
  description = "Email used to retrieve SSL certificates from Let's Encrypt"
}

variable "gke_version" {
  description = "Version of GKE to use for the GitLab cluster"
  default     = "1.16"
}

variable "gke_machine_type" {
  description = "Machine type used for the node-pool"
  default     = "n2-standard-4"
}

variable "gitlab_db_name" {
  description = "Instance name for the GitLab Postgres database."
  default     = "gitlab-db"
}

variable "gitlab_db_random_prefix" {
  description = "Sets random suffix at the end of the Cloud SQL instance name."
  default     = false
}

variable "gitlab_db_password" {
  description = "Password for the GitLab Postgres user. Leave blank to auto generate"
  default     = ""
}

variable "gitlab_root_password" {
  description = "Initial Password for the GitLab Root user. Leave blank to auto generate"
  default     = ""
}

variable "gitlab_address_name" {
  description = "Name of the address to use for GitLab ingress"
  default     = ""
}

variable "gitlab_runner_install" {
  description = "Choose whether to install the gitlab runner in the cluster"
  default     = true
}

variable "region" {
  default     = "us-central1"
  description = "GCP region to deploy resources to"
}

variable "services_cluster_nodes_subnet_cidr" {
  default     = "10.0.0.0/16"
  description = "Cidr range to use for gitlab GKE nodes subnet"
}

variable "services_cluster_pods_subnet_cidr" {
  default     = "10.3.0.0/16"
  description = "Cidr range to use for GKE Services pods subnet"
}

variable "services_cluster_services_subnet_cidr" {
  default     = "10.2.0.0/16"
  description = "Cidr range to use for GKE Services services subnet"
}
variable "helm_chart_version" {
  type        = string
  default     = "4.6.1"
  description = "Helm chart version to install during deployment"
}


variable "google_oauth2_client_secret" {
  # default = ""
  description = "Google Oauth2 Client Secret. Leave blank to skip"
}

variable "google_oauth2_client_id" {
  # default = ""
  description = "Google Oauth2 Client ID. Leave blank to skip"
}
