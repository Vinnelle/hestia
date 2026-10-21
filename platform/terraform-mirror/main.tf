resource "random_id" "bucket" {
  byte_length = 4
}

resource "linode_object_storage_bucket" "terraform_provider_mirror" {
  region = var.region
  label  = "hestia-providers-${random_id.bucket.hex}"
  acl    = "public-read"
}

resource "linode_object_storage_key" "ci" {
  label = "hestia-providers-ci"

  bucket_access {
    bucket_name = linode_object_storage_bucket.terraform_provider_mirror.label
    region      = linode_object_storage_bucket.terraform_provider_mirror.region
    permissions = "read_write"
  }
}

resource "gitlab_project_variable" "endpoint" {
  project   = var.gitlab_project_id
  key       = "TF_PROVIDER_MIRROR_ENDPOINT"
  value     = linode_object_storage_bucket.terraform_provider_mirror.s3_endpoint
  masked    = false
  protected = true
}

resource "gitlab_project_variable" "bucket" {
  project   = var.gitlab_project_id
  key       = "TF_PROVIDER_MIRROR_BUCKET"
  value     = linode_object_storage_bucket.terraform_provider_mirror.label
  masked    = false
  protected = true
}

resource "gitlab_project_variable" "access_key" {
  project   = var.gitlab_project_id
  key       = "TF_PROVIDER_MIRROR_ACCESS_KEY"
  value     = linode_object_storage_key.ci.access_key
  masked    = true
  protected = true
}

resource "gitlab_project_variable" "secret_key" {
  project   = var.gitlab_project_id
  key       = "TF_PROVIDER_MIRROR_SECRET_KEY"
  value     = linode_object_storage_key.ci.secret_key
  masked    = true
  protected = true
}
