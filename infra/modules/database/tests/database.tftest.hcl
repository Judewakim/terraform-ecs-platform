mock_provider "aws" {
  mock_resource "aws_db_instance" {
    defaults = {
      master_user_secret = [{
        secret_arn    = "arn:aws:secretsmanager:us-east-1:123456789012:secret:rds!db-mock"
        secret_status = "active"
        kms_key_id    = "mock"
      }]
    }
  }
}

variables {
  name          = "test"
  vpc_id        = "vpc-123"
  db_subnet_ids = ["subnet-a", "subnet-b"]
  kms_key_arn   = "arn:aws:kms:us-east-1:123456789012:key/mock"
}

run "private_encrypted_managed_password" {
  command = plan

  assert {
    condition     = aws_db_instance.this.publicly_accessible == false
    error_message = "The database must not be publicly accessible."
  }
  assert {
    condition     = aws_db_instance.this.storage_encrypted
    error_message = "Storage must be encrypted."
  }
  assert {
    condition     = aws_db_instance.this.manage_master_user_password
    error_message = "The password must be generated and held by Secrets Manager, never in state."
  }
  assert {
    condition     = aws_db_instance.this.deletion_protection
    error_message = "Deletion protection should default to on."
  }
}

run "forces_tls" {
  command = plan

  assert {
    condition     = anytrue([for p in aws_db_parameter_group.this.parameter : p.name == "rds.force_ssl" && p.value == "1"])
    error_message = "rds.force_ssl must be 1."
  }
}
