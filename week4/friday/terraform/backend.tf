# Remote state in S3 with locking.
#
# Partial configuration: the bucket name contains the AWS account ID and the
# region is chosen at run time, so pipeline.sh supplies both with
#   terraform init -backend-config="bucket=..." -backend-config="region=..."
# The bucket itself is created once by terraform/bootstrap/.
#
# use_lockfile = true makes Terraform write a .tflock object next to the state
# with a conditional S3 write. A second apply started while the first is still
# running fails with "Error acquiring the state lock" instead of corrupting the
# state. Before Terraform 1.10 this needed a separate DynamoDB table.
terraform {
  backend "s3" {
    key          = "week4/friday/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
