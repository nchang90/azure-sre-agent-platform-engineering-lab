# Custom instructions

`scripts/apply-extras.sh <environment>` selects custom instructions from the
environment tfvars `tags.scenario` value.

Add a scenario-specific file named `<scenario>.txt` in this directory, for
example `s2.txt` or `s4.txt`. If no scenario file exists, the script applies
`default.txt`.
