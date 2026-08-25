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
