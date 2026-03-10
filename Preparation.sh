#! /bin/bash

sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo 
sudo yum install terraform -y
sudo mkdir /home/airflow
cd /home/airflow
git clone https://github.com/nico-its/airflow.git
