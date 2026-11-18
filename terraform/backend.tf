# State lives in Contabo Object Storage (S3 API). Bucket and key per
# environment come from envs/<env>.s3.tfbackend at init time; credentials
# from AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY.
terraform {
  backend "s3" {
    region = "eu-central-1" # ignored by Contabo, but required by the backend

    use_path_style              = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true

    # lock file next to the state object, no DynamoDB needed
    use_lockfile = true
  }
}
