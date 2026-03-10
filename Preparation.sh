#! /bin/bash

sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo 
sudo yum install terraform -y

terraform init
terraform plan
terraform apply
