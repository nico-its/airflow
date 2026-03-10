#! /bin/bash

sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo 
sudo yum install terraform -y
cd terraform-airflow
sudo terraform init
sudo terraform plan -out plan.tfplan
sudo terraform apply -auto-approve