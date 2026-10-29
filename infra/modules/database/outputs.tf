output "address" {
  value = aws_db_instance.this.address
}

output "port" {
  value = aws_db_instance.this.port
}

output "db_name" {
  value = aws_db_instance.this.db_name
}

output "identifier" {
  value = aws_db_instance.this.identifier
}

output "security_group_id" {
  value = aws_security_group.db.id
}

output "master_secret_arn" {
  description = "Secrets Manager secret holding username and password (JSON)."
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}
