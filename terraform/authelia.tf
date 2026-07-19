# Obsolete Authelia LXC container configuration removed (Migrated to K3s Kubernetes cluster).

resource "random_password" "authelia_jwt_secret" {
  length  = 64
  special = false
}

resource "random_password" "authelia_session_secret" {
  length  = 64
  special = false
}

resource "random_password" "authelia_encryption_key" {
  length  = 64
  special = false
}
