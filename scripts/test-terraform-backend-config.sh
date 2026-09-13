#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

environments=(demo dev sbox)
keys=()

for environment in "${environments[@]}"; do
  backend_file="infra/terraform/backend/${environment}.backend.tfvars"
  expected_key="${environment}_azuresre.tfstate"
  actual_key="$(awk -F'"' '/^key[[:space:]]*=/{print $2}' "$backend_file")"

  if [[ "$actual_key" != "$expected_key" ]]; then
    echo "Expected $backend_file to use state key $expected_key, found ${actual_key:-<missing>}." >&2
    exit 1
  fi

  keys+=("$actual_key")
done

unique_key_count="$(printf '%s\n' "${keys[@]}" | sort -u | wc -l | tr -d '[:space:]')"

if [[ "$unique_key_count" != "${#environments[@]}" ]]; then
  echo "Each backend tfvars file must use a unique Terraform state key." >&2
  exit 1
fi

echo "Terraform backend state keys are environment-specific and unique."
