output "instance_name" {
  value = aws_instance.airflow.tags["Name"]
}

output "instance_public_ip" {
  value = aws_instance.airflow.public_ip
}

output "airflow_url" {
  value = "http://${aws_instance.airflow.public_ip}:8080"
}

output "airflow_credentials" {
  value = {
    user     = var.airflow_admin_user
    password = var.airflow_admin_password
  }
  sensitive = true
}