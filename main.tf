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

provider "google" {
  project = var.project_id
}

provider "google-beta" {
  project = var.project_id
}

locals {
  gitlab_db_name = var.gitlab_db_random_prefix ? "${var.gitlab_db_name}-${random_id.suffix[0].hex}" : var.gitlab_db_name
}

resource "random_id" "suffix" {
  count = var.gitlab_db_random_prefix ? 1 : 0

  byte_length = 4
}

provider "helm" {
  kubernetes {
    load_config_file       = false
    host                   = google_container_cluster.services.endpoint
    client_key             = base64decode(google_container_cluster.services.master_auth.0.client_key)
    client_certificate     = base64decode(google_container_cluster.services.master_auth.0.client_certificate)
    cluster_ca_certificate = base64decode(google_container_cluster.services.master_auth.0.cluster_ca_certificate)
  }
}

provider "kubernetes" {
  load_config_file       = false
  host                   = google_container_cluster.services.endpoint
  client_key             = base64decode(google_container_cluster.services.master_auth.0.client_key)
  client_certificate     = base64decode(google_container_cluster.services.master_auth.0.client_certificate)
  cluster_ca_certificate = base64decode(google_container_cluster.services.master_auth.0.cluster_ca_certificate)
}

resource "google_project" "project" {
  project_id      = var.project_id
  name            = var.project_id
  org_id          = var.organization_id
  folder_id       = var.folder_id
  billing_account = var.billing_account
}

// Services
module "project_services" {
  source  = "terraform-google-modules/project-factory/google//modules/project_services"
  version = "~> 9.0"

  project_id                  = google_project.project.project_id
  disable_services_on_destroy = false

  activate_apis = [
    "compute.googleapis.com",
    "container.googleapis.com",
    "servicenetworking.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "redis.googleapis.com"
  ]
}

// GCS Service Account
resource "google_service_account" "gitlab_gcs" {
  project      = var.project_id
  account_id   = "gitlab-gcs"
  display_name = "GitLab Cloud Storage"
}

resource "google_service_account_key" "gitlab_gcs" {
  service_account_id = google_service_account.gitlab_gcs.name
}

resource "google_project_iam_member" "project" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.gitlab_gcs.email}"
}

// Networking
resource "google_compute_network" "services" {
  name                    = "services"
  project                 = module.project_services.project_id
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "services_cluster" {
  name          = "gke"
  ip_cidr_range = var.services_cluster_nodes_subnet_cidr
  region        = var.region
  network       = google_compute_network.services.self_link

  secondary_ip_range {
    range_name    = "services-cluster-pod-cidr"
    ip_cidr_range = var.services_cluster_pods_subnet_cidr
  }

  secondary_ip_range {
    range_name    = "services-cluster-service-cidr"
    ip_cidr_range = var.services_cluster_services_subnet_cidr
  }
}

resource "google_compute_address" "gitlab" {
  name         = "gitlab"
  region       = var.region
  address_type = "EXTERNAL"
  description  = "Gitlab Ingress IP"
  depends_on   = [module.project_services.project_id]
  count        = var.gitlab_address_name == "" ? 1 : 0
}

// Database
resource "google_compute_global_address" "gitlab_sql" {
  provider      = google-beta
  project       = var.project_id
  name          = "gitlab-sql"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  network       = google_compute_network.services.self_link
  address       = "10.1.0.0"
  prefix_length = 16
}

resource "google_service_networking_connection" "private_vpc_connection" {
  provider                = google-beta
  network                 = google_compute_network.services.self_link
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.gitlab_sql.name]
  depends_on              = [module.project_services.project_id]
}

resource "google_sql_database_instance" "gitlab_db" {
  depends_on       = [google_service_networking_connection.private_vpc_connection]
  name             = local.gitlab_db_name
  region           = var.region
  database_version = "POSTGRES_13"

  settings {
    tier            = "db-custom-4-15360"
    disk_autoresize = true

    ip_configuration {
      ipv4_enabled    = "false"
      private_network = google_compute_network.services.self_link
    }
  }
}

resource "google_sql_database" "gitlabhq_production" {
  name       = "gitlabhq_production"
  instance   = google_sql_database_instance.gitlab_db.name
  depends_on = [google_sql_user.gitlab]
}

resource "random_string" "autogenerated_gitlab_db_password" {
  length  = 16
  special = false
}

resource "random_string" "autogenerated_gitlab_root_password" {
  length  = 16
  special = false
}

resource "google_sql_user" "gitlab" {
  name     = "gitlab"
  instance = google_sql_database_instance.gitlab_db.name

  password = var.gitlab_db_password != "" ? var.gitlab_db_password : random_string.autogenerated_gitlab_db_password.result
}

// Redis
resource "google_redis_instance" "gitlab" {
  name               = "gitlab"
  tier               = "STANDARD_HA"
  memory_size_gb     = 5
  region             = var.region
  authorized_network = google_compute_network.services.self_link

  depends_on = [module.project_services.project_id]

  display_name = "GitLab Redis"
}

// Cloud Storage
resource "google_storage_bucket" "gitlab-backups" {
  name     = "${var.project_id}-gitlab-backups"
  location = var.region
}

resource "google_storage_bucket" "gitlab-uploads" {
  name     = "${var.project_id}-gitlab-uploads"
  location = var.region
}

resource "google_storage_bucket" "gitlab-artifacts" {
  name     = "${var.project_id}-gitlab-artifacts"
  location = var.region
}

resource "google_storage_bucket" "git-lfs" {
  name     = "${var.project_id}-git-lfs"
  location = var.region
}

resource "google_storage_bucket" "gitlab-packages" {
  name     = "${var.project_id}-gitlab-packages"
  location = var.region
}

resource "google_storage_bucket" "gitlab-registry" {
  name     = "${var.project_id}-registry"
  location = var.region
}

resource "google_storage_bucket" "gitlab-pseudo" {
  name     = "${var.project_id}-pseudo"
  location = var.region
}

resource "google_storage_bucket" "gitlab-runner-cache" {
  name     = "${var.project_id}-runner-cache"
  location = var.region
}
// GKE Cluster
resource "google_container_cluster" "services" {
  name                     = var.kubernetes_cluster_name
  project                  = module.project_services.project_id
  location                 = var.region
  min_master_version       = var.gke_version
  remove_default_node_pool = true
  initial_node_count       = 1

  master_auth {
    username = ""
    password = ""

    client_certificate_config {
      issue_client_certificate = true
    }
  }

  network    = google_compute_network.services.name
  subnetwork = google_compute_subnetwork.services_cluster.name
  ip_allocation_policy {
    cluster_secondary_range_name  = "services-cluster-pod-cidr"
    services_secondary_range_name = "services-cluster-services-cidr"
  }
}

resource "google_container_node_pool" "services_4c16g" {
  name       = "standard_4c_16g"
  node_count = 1
  location   = var.region
  cluster    = google_container_cluster.services.name

  autoscaling {
    min_node_count = 1
    max_node_count = 3
  }
  node_config {
    machine_type = var.gke_machine_type
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }
}

resource "kubernetes_storage_class" "pd-ssd" {
  metadata {
    name = "pd-ssd"
  }

  storage_provisioner = "kubernetes.io/gce-pd"

  parameters = {
    type = "pd-ssd"
  }
}

resource "kubernetes_secret" "gitlab_pg" {
  metadata {
    name = "gitlab-pg"
  }

  data = {
    password = var.gitlab_db_password != "" ? var.gitlab_db_password : random_string.autogenerated_gitlab_db_password.result
  }
}

resource "kubernetes_secret" "gitlab_initial_root_password" {
  metadata {
    name = "pre-created-gitlab-initial-root-password"
  }

  data = {
    password = var.gitlab_root_password != "" ? var.gitlab_root_password : random_string.autogenerated_gitlab_root_password.result
  }
}

resource "kubernetes_secret" "gitlab_oauth_providers" {
  count = var.google_oauth2_client_secret != "" && var.google_oauth2_client_id != "" ? 1 : 0
  metadata {
    name = "gitlab-oauth-providers"
  }
  data = {
    # google_oauth2 = "name: google_oauth2\nlabel: Google\napp_id: ${google_iap_client.gitlab_client.client_id}\napp_secret: ${google_iap_client.gitlab_client.secret}\nargs:\n\taccess_type: 'offline'\n\tapproval_prompt: ''"
    google_oauth2 = "name: google_oauth2\nlabel: Google\napp_id: ${var.google_oauth2_client_id}\napp_secret: ${var.google_oauth2_client_secret}\nargs:\n\taccess_type: 'offline'\n\tapproval_prompt: ''"
  }
}
resource "kubernetes_secret" "gitlab_rails_storage" {
  metadata {
    name = "gitlab-rails-storage"
  }

  data = {
    connection = <<EOT
provider: Google
google_project: ${var.project_id}
google_client_email: ${google_service_account.gitlab_gcs.email}
google_json_key_string: '${base64decode(google_service_account_key.gitlab_gcs.private_key)}'
EOT
  }
}

resource "kubernetes_secret" "gitlab_registry_storage" {
  metadata {
    name = "gitlab-registry-storage"
  }

  data = {
    "gcs.json" = <<EOT
${base64decode(google_service_account_key.gitlab_gcs.private_key)}
EOT
    storage    = <<EOT
gcs:
  bucket: ${var.project_id}-registry
  keyfile: /etc/docker/registry/storage/gcs.json
EOT
  }
}


resource "kubernetes_secret" "gitlab_gcs_credentials" {
  metadata {
    name = "google-application-credentials"
  }

  data = {
    gcs-application-credentials-file = base64decode(google_service_account_key.gitlab_gcs.private_key)
  }
}

data "google_compute_address" "gitlab" {
  name   = var.gitlab_address_name
  region = var.region

  # Do not get data if the address is being created as part of the run
  count = var.gitlab_address_name == "" ? 0 : 1
}

locals {
  gitlab_address   = var.gitlab_address_name == "" ? google_compute_address.gitlab.0.address : data.google_compute_address.gitlab.0.address
  domain           = var.domain != "" ? var.domain : "${local.gitlab_address}.xip.io"
  extras_file_path = var.google_oauth2_client_secret != "" ? "${path.module}/values-extras-with-oauth.yaml.tpl" : "${path.module}/values-extras.yaml.tpl"
}

data "template_file" "helm_values" {
  template = file("${path.module}/values.yaml.tpl")

  vars = {
    DOMAIN                = local.domain
    INGRESS_IP            = local.gitlab_address
    DB_PRIVATE_IP         = google_sql_database_instance.gitlab_db.private_ip_address
    REDIS_PRIVATE_IP      = google_redis_instance.gitlab.host
    PROJECT_ID            = var.project_id
    CERT_MANAGER_EMAIL    = var.certmanager_email
    GITLAB_RUNNER_INSTALL = var.gitlab_runner_install
  }
}

data "template_file" "helm_values_extras" {
  template = file(local.extras_file_path)
}

resource "time_sleep" "sleep_for_cluster_fix_helm_6361" {
  create_duration  = "180s"
  destroy_duration = "180s"
  depends_on       = [google_container_cluster.services, google_sql_database.gitlabhq_production]
}

resource "helm_release" "gitlab" {
  name       = "gitlab"
  repository = "https://charts.gitlab.io"
  chart      = "gitlab"
  version    = var.helm_chart_version
  timeout    = 1200

  values = [
    data.template_file.helm_values.rendered,
    data.template_file.helm_values_extras.rendered
  ]

  depends_on = [
    google_redis_instance.gitlab,
    google_sql_user.gitlab,
    kubernetes_storage_class.pd-ssd,
    time_sleep.sleep_for_cluster_fix_helm_6361,
  ]
}
