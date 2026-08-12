import {
  to = aws_s3_bucket.terraform_provider_mirror
  id = "providers"
}

resource "aws_s3_bucket" "terraform_provider_mirror" {
  provider = aws.mega_s4
  bucket   = "providers"
}

resource "aws_s3_bucket_policy" "terraform_provider_mirror_public_read" {
  provider = aws.mega_s4
  bucket   = aws_s3_bucket.terraform_provider_mirror.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicReadMirror"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.terraform_provider_mirror.arn}/*"
    }]
  })
}

output "terraform_provider_mirror_url" {
  description = "Base URL for the provider_installation network_mirror block CI writes into .terraformrc -- must match TF_PROVIDER_MIRROR_URL in .gitlab-ci.yml."
  value       = "https://s3.${var.mega_s4_endpoint_domain}/${aws_s3_bucket.terraform_provider_mirror.bucket}/"
}
