output "instance_public_ips" {
  value = {
    for k, v in aws_instance.airflow : k => v.public_ip
  }
}

output "airflow_urls" {
  value = {
    for k, v in aws_instance.airflow : k => "http://${v.public_ip}:8080"
  }
}

output "instance_names" {
  value = keys(aws_instance.airflow)
}