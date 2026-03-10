variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-1"
}


variable "instance_type" {
  description = "Type d'instance EC2 autorisé"
  type        = string
  default     = "t2.micro"

  validation {
    condition     = contains(["t2.nano", "t2.micro", "t2.small", "t3.nano", "t3.micro", "t3.small"], var.instance_type)
    error_message = "Le type d'instance doit être nano, micro ou small."
  }
}

variable "disk_size" {
  description = "Taille du disque root en Go"
  type        = number
  default     = 20
}

variable "owner" {
  description = "Email ITS du créateur"
  type        = string
}

variable "airflow_version" {
  description = "Version d'Apache Airflow"
  type        = string
  default     = "3.1.7"
}

variable "airflow_admin_user" {
  description = "Utilisateur admin Airflow"
  type        = string
  default     = "admin"
}

variable "airflow_admin_password" {
  description = "Mot de passe admin Airflow"
  type        = string
  sensitive   = true
}

variable "git_dags_repo_url" {
  description = "Votre URL du repository GitLab contenant les DAGs"
  type        = string
}

variable "git_dags_branch" {
  description = "Votre Branche GitLab contenant les DAGs"
  type        = string
}