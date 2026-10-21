resource "aws_s3_bucket" "pbs" {
  provider = aws.mega_s4
  bucket   = "hestia-pbs"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket" "import" {
  provider = aws.mega_s4
  bucket   = "hestia-import"
}
