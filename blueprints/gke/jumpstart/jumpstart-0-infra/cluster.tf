/**
 * Copyright 2023 Google LLC
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

locals {
  _cluster_sa = (
    var.create_cluster == null
    ? data.google_container_cluster.cluster.0.node_config.0.service_account
    : module.cluster-service-account.0.email
  )
  cluster_sa = (
    local._cluster_sa == "default"
    ? module.project.service_accounts.default.compute
    : local._cluster_sa
  )
  cluster_sa_roles = [
    "roles/artifactregistry.reader",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer"
  ]
  cluster_vpc = (
    local.use_shared_vpc || !local.create_vpc
    # cluster variable configures networking
    ? {
      network = try(
        var.create_cluster.vpc.id, null
      )
      secondary_range_names = try(
        var.create_cluster.vpc.secondary_range_names, null
      )
      subnet = try(
        var.create_cluster.vpc.subnet_id, null
      )
    }
    # VPC creation configures networking
    : {
      network               = module.vpc.0.id
      secondary_range_names = { pods = "pods", services = "services" }
      subnet                = module.vpc.0.subnet_ids["${var.region}/${var.prefix}-default"]
    }
  )
}

data "google_container_cluster" "cluster" {
  count    = var.create_cluster == null ? 1 : 0
  project  = var.project_id
  location = var.region
  name     = var.cluster_name
}

module "cluster-service-account" {
  source     = "../../../../modules/iam-service-account"
  count      = var.create_cluster != null ? 1 : 0
  project_id = module.project.project_id
  name       = var.prefix
  iam_project_roles = {
    (module.project.project_id) = local.cluster_sa_roles
  }
}

module "cluster" {
  source     = "../../../../modules/gke-cluster-autopilot"
  count      = var.create_cluster != null ? 1 : 0
  project_id = module.project.project_id
  name       = var.cluster_name
  location   = var.region
  vpc_config = {
    network                  = local.cluster_vpc.network
    subnetwork               = local.cluster_vpc.subnet
    secondary_range_names    = local.cluster_vpc.secondary_range_names
    master_authorized_ranges = var.create_cluster.master_authorized_ranges
    master_ipv4_cidr_block   = var.create_cluster.master_ipv4_cidr_block
  }
  private_cluster_config = {
    enable_private_endpoint = true
    master_global_access    = true
  }
  service_account = module.cluster-service-account.0.email
  labels          = var.create_cluster.labels
}

resource "google_project_iam_member" "cluster_sa" {
  for_each = toset(var.create_cluster == null ? [] : local.cluster_sa_roles)
  project  = module.project.project_id
  role     = each.key
  member   = "serviceAccount:${local.cluster_sa}"
}
