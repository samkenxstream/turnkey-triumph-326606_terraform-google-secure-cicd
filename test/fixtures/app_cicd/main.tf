/**
 * Copyright 2021 Google LLC
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
  envs = ["dev", "qa", "prod"]
}

module "example" {
  source = "../../../examples/app_cicd"

  project_id       = var.project_id
  primary_location = var.primary_location
  deploy_branch_clusters = {
    prod = {
      cluster      = "prod-cluster",
      project_id   = module.gke-project["prod"].project_id,
      location     = var.primary_location,
      attestations = ["projects/${var.project_id}/attestors/security-attestor", "projects/${var.project_id}/attestors/quality-attestor", "projects/${var.project_id}/attestors/build-attestor"]
    },
    qa = {
      cluster      = "qa-cluster",
      project_id   = module.gke-project["qa"].project_id,
      location     = var.primary_location,
      attestations = ["projects/${var.project_id}/attestors/security-attestor", "projects/${var.project_id}/attestors/build-attestor"]

    }
    dev = {
      cluster      = "dev-cluster",
      project_id   = module.gke-project["dev"].project_id,
      location     = var.primary_location,
      attestations = ["projects/${var.project_id}/attestors/security-attestor"]
    },
  }
}

////// GKE Projects
module "gke-project" {
  for_each = toset(local.envs)
  source  = "terraform-google-modules/project-factory/google"
  version = "~> 10.0"

  name              = "secure-cicd-gke-${each.key}"
  random_project_id = "true"
  org_id            = var.org_id
  folder_id         = var.folder_id
  billing_account   = var.billing_account
  default_service_account = "keep"

  activate_apis = [
    "cloudresourcemanager.googleapis.com",
    "storage-api.googleapis.com",
    "serviceusage.googleapis.com",
    "cloudbuild.googleapis.com",
    "containerregistry.googleapis.com",
    "iamcredentials.googleapis.com",
    "secretmanager.googleapis.com",
    "sourcerepo.googleapis.com",
    "artifactregistry.googleapis.com",
    "containeranalysis.googleapis.com",
    "cloudkms.googleapis.com",
    "binaryauthorization.googleapis.com",
    "containerscanning.googleapis.com",
    "container.googleapis.com",
  ]
}

////// VPCs
module "vpc" {
    for_each = toset(local.envs)
    source  = "terraform-google-modules/network/google"
    version = "~> 3.0"

    project_id   = module.gke-project[each.value].project_id
    network_name = "default"
    routing_mode = "REGIONAL"

    auto_create_subnetworks = true

    firewall_rules = [
      {
        name = "default-allow-icmp"
        direction = "INGRESS"
        priority = 65534
        ranges                  = ["0.0.0.0/0"]
        allow = [{
          protocol = "icmp"
        }]
      },
      {
        name = "default-allow-internal"
        direction = "INGRESS"
        priority = 65534
        ranges                  = ["10.128.0.0/9"]
        allow = [{
          protocol = "all"
        }]
      },
      {
        name = "default-allow-rdp"
        direction = "INGRESS"
        priority = 65534
        ranges                  = ["0.0.0.0/0"]
        allow = [{
          protocol = "tcp"
          ports = ["3389"]
        }]
      },
      {
        name = "default-allow-ssh"
        direction = "INGRESS"
        priority = 65534
        ranges                  = ["0.0.0.0/0"]
        allow = [{
          protocol = "tcp"
          ports = ["22"]
        }]
      }
    ]

    # secondary_ranges = {
    #     subnet-01 = [
    #         {
    #             range_name    = "subnet-01-secondary-01"
    #             ip_cidr_range = "192.168.64.0/24"
    #         },
    #     ]

    #     subnet-02 = []
    # }

    # routes = [
    #     {
    #         name                   = "egress-internet"
    #         description            = "route through IGW to access internet"
    #         destination_range      = "0.0.0.0/0"
    #         tags                   = "egress-inet"
    #         next_hop_internet      = "true"
    #     },
    #     {
    #         name                   = "app-proxy"
    #         description            = "route through proxy to reach app"
    #         destination_range      = "10.50.10.0/24"
    #         tags                   = "app-proxy"
    #         next_hop_instance      = "app-proxy-instance"
    #         next_hop_instance_zone = "us-west1-a"
    #     },
    # ]
}


////// GKE Clusters
resource "google_container_cluster" "cluster" {
  for_each = toset(local.envs)

  name                     = "${each.value}-cluster"
  location                 = var.primary_location
  project = module.gke-project[each.value].project_id

  network                  = "default"

  # Enable Autopilot for this cluster
  enable_autopilot = true

  # Configuration options for the Release channel feature, which provide more control over automatic upgrades of your GKE clusters.
  release_channel {
    channel = "REGULAR"
  }
}