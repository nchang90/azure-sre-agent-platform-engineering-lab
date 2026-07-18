# Quickstart

1) terraform -chdir=infra/terraform init
2) terraform -chdir=infra/terraform apply -auto-approve -var-file=environments/demo.tfvars
3) bash scripts/apply-extras.sh demo
4) Walk a scenario in scenarios/ (S3 currently available)
