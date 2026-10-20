# Remote state. Bucket and table are created once by scripts/bootstrap-state.sh.
# Backend blocks cannot use variables, so the account ID is literal.
terraform {
  backend "s3" {
    bucket         = "petclinic-terraform-state-225989338539"
    key            = "petclinic/dev/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "petclinic-terraform-locks"
    encrypt        = true
  }
}
