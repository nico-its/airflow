# Terraform Airflow EC2

## Fichiers
- main.tf
- variables.tf
- versions.tf
- outputs.tf
- userdata.sh.tpl
- terraform.tfvars.example

## Prérequis

Avoir un répertoire git public pour renseigner son url et sa branch

## Utilisation
1. Dans votre CloudShell , lancer ces commandes : 
```bash
    sudo mkdir /home/airflow && cd /home/airflow && sudo git clone https://github.com/Ramy-BenIkhelef/Airflow_formation.git && cd Airflow_formation && sudo chmod 755 Preparation.sh ./terraform-airflow/airflow.sh && ./Preparation.sh
```
2. Indiquez votre mail ITS , l'url git indiquée en prérequis et la branch lorsque c'est demandé.
3. Attendre 5 min
4. Rendez vous sur Airflow via l'url indiqué à la fin du déploiement.
