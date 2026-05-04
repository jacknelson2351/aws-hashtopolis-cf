resource "aws_secretsmanager_secret" "admin_password" {
  name                    = "hashtopolis/admin-password"
  description             = "Hashtopolis admin password. TF generates and seeds; the server bootstrap rotates the live admin user to this value."
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret" "voucher" {
  name                    = "hashtopolis/voucher"
  description             = "Hashtopolis multi-use agent voucher. Created by the server bootstrap on first boot."
  recovery_window_in_days = 0
}

resource "random_password" "admin" {
  length  = 24
  special = false
}

resource "aws_secretsmanager_secret_version" "admin_password" {
  secret_id     = aws_secretsmanager_secret.admin_password.id
  secret_string = random_password.admin.result
}
