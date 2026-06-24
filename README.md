# terraform-gcp
Google Cloud Terraform deployment script for Cloud Shell
This script automates a Terraform-based Google Cloud deployment from Cloud Shell. It creates a custom VPC, two regional subnets, two Compute Engine VM instances, an HTTP firewall rule, and a Cloud Storage bucket used as a Terraform remote state backend. It removes tutorial/promotional content and keeps only the required deployment logic.

curl -LO raw.githubusercontent.com/neo4jrohitpal/terraform-gcp/refs/heads/main/rohit-gcp-terraform.sh
sudo chmod +x rohit-gcp-terraform.sh 
./rohit-gcp-terraform.sh
