output "instance_public_ips" {
  value = {
    for k, v in aws_instance.airflow : k => v.public_ip
  }
}

output "instance_private_ips" {
  value = {
    for k, v in aws_instance.airflow : k => v.private_ip
  }
}

output "airflow_urls" {
  value = {
    for k, v in aws_instance.airflow : k => "http://${v.public_ip}:8080"
  }
}