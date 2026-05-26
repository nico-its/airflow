output "instance_name" {
  value = aws_instance.airflow.tags["Name"]
}

output "instance_public_ip" {
  value = aws_instance.airflow.public_ip
}

output "airflow_url" {
  value = "https://${aws_instance.airflow.public_ip}:443"
}
