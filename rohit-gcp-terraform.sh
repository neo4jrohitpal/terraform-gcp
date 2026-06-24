#!/usr/bin/env bash
set -euo pipefail

# Clean Terraform deployment script for Google Cloud Shell.
# This script creates Terraform files and deploys:
# - Two Compute Engine instances
# - One Cloud Storage bucket
# - GCS backend configuration for Terraform state
# - One custom VPC with two subnets
# - One firewall rule allowing TCP/80

read -rp "Enter your bucket name: " BUCKET
read -rp "Enter your VPC name: " VPC
read -rp "Enter your zone (example: us-central1-a): " ZONE

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
REGION="${ZONE%-*}"
WORKDIR="$HOME/cleaned-gcp-terraform"

if [[ -z "${PROJECT_ID}" ]]; then
  echo "Could not determine PROJECT_ID. Run: gcloud config set project YOUR_PROJECT_ID"
  exit 1
fi

if [[ -z "${BUCKET}" || -z "${VPC}" || -z "${ZONE}" ]]; then
  echo "Bucket name, VPC name, and zone are required."
  exit 1
fi

echo "Using project: ${PROJECT_ID}"
echo "Using region:  ${REGION}"
echo "Using zone:    ${ZONE}"
echo "Working dir:   ${WORKDIR}"

gcloud config set project "${PROJECT_ID}"
gcloud config set compute/zone "${ZONE}"
gcloud config set compute/region "${REGION}"

mkdir -p "${WORKDIR}/modules/instances" "${WORKDIR}/modules/storage"
cd "${WORKDIR}"

cat > versions.tf <<EOF_TF
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.53.0"
    }
  }
}
EOF_TF

cat > variables.tf <<EOF_TF
variable "project_id" {
  type    = string
  default = "${PROJECT_ID}"
}

variable "region" {
  type    = string
  default = "${REGION}"
}

variable "zone" {
  type    = string
  default = "${ZONE}"
}

variable "bucket_name" {
  type    = string
  default = "${BUCKET}"
}

variable "vpc_name" {
  type    = string
  default = "${VPC}"
}
EOF_TF

cat > providers.tf <<EOF_TF
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}
EOF_TF

cat > main.tf <<'EOF_TF'
module "instances" {
  source   = "./modules/instances"
  zone     = var.zone
  vpc_name = var.vpc_name
}

module "storage" {
  source      = "./modules/storage"
  bucket_name = var.bucket_name
}

module "vpc" {
  source  = "terraform-google-modules/network/google"
  version = "~> 6.0.0"

  project_id   = var.project_id
  network_name = var.vpc_name
  routing_mode = "GLOBAL"

  subnets = [
    {
      subnet_name   = "subnet-01"
      subnet_ip     = "10.10.10.0/24"
      subnet_region = var.region
    },
    {
      subnet_name           = "subnet-02"
      subnet_ip             = "10.10.20.0/24"
      subnet_region         = var.region
      subnet_private_access = true
      subnet_flow_logs      = true
    }
  ]
}

resource "google_compute_firewall" "tf_firewall" {
  name    = "tf-firewall"
  network = module.vpc.network_name

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["web"]
}
EOF_TF

cat > outputs.tf <<'EOF_TF'
output "project_id" {
  value = var.project_id
}

output "region" {
  value = var.region
}

output "zone" {
  value = var.zone
}

output "bucket_name" {
  value = module.storage.bucket_name
}

output "vpc_name" {
  value = module.vpc.network_name
}
EOF_TF

cat > modules/instances/variables.tf <<'EOF_TF'
variable "zone" {
  type = string
}

variable "vpc_name" {
  type = string
}
EOF_TF

cat > modules/instances/instances.tf <<'EOF_TF'
resource "google_compute_instance" "tf_instance_1" {
  name         = "tf-instance-1"
  machine_type = "e2-standard-2"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  network_interface {
    network    = var.vpc_name
    subnetwork = "subnet-01"
  }

  tags = ["web"]

  allow_stopping_for_update = true
}

resource "google_compute_instance" "tf_instance_2" {
  name         = "tf-instance-2"
  machine_type = "e2-standard-2"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  network_interface {
    network    = var.vpc_name
    subnetwork = "subnet-02"
  }

  allow_stopping_for_update = true
}
EOF_TF

cat > modules/instances/outputs.tf <<'EOF_TF'
output "instance_names" {
  value = [
    google_compute_instance.tf_instance_1.name,
    google_compute_instance.tf_instance_2.name
  ]
}
EOF_TF

cat > modules/storage/variables.tf <<'EOF_TF'
variable "bucket_name" {
  type = string
}
EOF_TF

cat > modules/storage/storage.tf <<'EOF_TF'
resource "google_storage_bucket" "storage_bucket" {
  name                        = var.bucket_name
  location                    = "US"
  force_destroy               = true
  uniform_bucket_level_access = true
}
EOF_TF

cat > modules/storage/outputs.tf <<'EOF_TF'
output "bucket_name" {
  value = google_storage_bucket.storage_bucket.name
}
EOF_TF

terraform init
terraform fmt -recursive
terraform validate
terraform apply -auto-approve

cat > backend.tf <<EOF_TF
terraform {
  backend "gcs" {
    bucket = "${BUCKET}"
    prefix = "terraform/state"
  }
}
EOF_TF

terraform init -migrate-state -force-copy
terraform apply -auto-approve

echo "Deployment complete. Terraform files are in: ${WORKDIR}"
