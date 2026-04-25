output "ec2_public_ip" {
  description = "Elastic IP of the application server — share with all team members"
  value       = aws_eip.app.public_ip
}

output "ec2_public_dns" {
  description = "Public DNS hostname of the EC2 instance"
  value       = aws_instance.app.public_dns
}

output "rds_endpoint" {
  description = "RDS MySQL endpoint (private — only reachable from EC2)"
  value       = aws_db_instance.mysql.endpoint
  sensitive   = true
}

output "rds_port" {
  description = "RDS MySQL port"
  value       = aws_db_instance.mysql.port
}

output "kms_key_id" {
  description = "KMS Key ID for encrypting secrets — add to your CI/CD secrets as KMS_KEY_ID"
  value       = aws_kms_key.secrets.key_id
}

output "kms_key_arn" {
  description = "KMS Key ARN"
  value       = aws_kms_key.secrets.arn
}

output "cloudwatch_log_group_app" {
  description = "CloudWatch log group for application logs"
  value       = aws_cloudwatch_log_group.app.name
}

output "ssm_db_host_parameter" {
  description = "SSM Parameter Store path for DB_HOST"
  value       = aws_ssm_parameter.db_host.name
}

output "ssm_db_name_parameter" {
  description = "SSM Parameter Store path for DB_NAME"
  value       = aws_ssm_parameter.db_name.name
}

output "ssm_db_user_parameter" {
  description = "SSM Parameter Store path for DB_USER"
  value       = aws_ssm_parameter.db_user.name
}

output "ssm_db_pass_parameter" {
  description = "SSM Parameter Store path for DB_PASS"
  value       = aws_ssm_parameter.db_pass.name
  sensitive   = true
}

output "ssm_jwt_secret_parameter" {
  description = "SSM Parameter Store path for JWT_SECRET"
  value       = aws_ssm_parameter.jwt_secret.name
}

output "ssm_kms_key_id_parameter" {
  description = "SSM Parameter Store path for KMS_KEY_ID"
  value       = aws_ssm_parameter.kms_key_id.name
}
