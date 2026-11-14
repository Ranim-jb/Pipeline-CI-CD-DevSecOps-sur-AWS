# SCÉNARIO 3 : bucket S3 volontairement public (à ne JAMAIS appliquer).
# Utilisation : cp scenarios/demo_s3_public.tf.txt terraform/demo_s3_public.tf
resource "aws_s3_bucket" "demo_public" {
  bucket = "devsecops-demo-public-CHANGER-MOI-123456"
}

resource "aws_s3_bucket_public_access_block" "demo_public" {
  bucket                  = aws_s3_bucket.demo_public.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}
