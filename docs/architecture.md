# Architecture

High-level view of the Azure SRE Agent lab, shared infra, and scenario flows.

- Shared infra: infra/terraform (environments/ today; modules/ TBD)
- Scenarios under scenarios/ (S3 today; S1/S2/S4 TBD; legacy scenario docs remain under docs/)
- Recipes and skills under /recipes and .github/skills

## Documentation Images

All documentation images are stored under `docs/images/`. Markdown files that reference diagrams or screenshots should use relative paths pointing to this directory (e.g. `../../docs/images/story1.png` from a file under `scenarios/`). Do not place images in a top-level `images/` folder or inside individual scenario directories — keeping assets in `docs/images/` follows the Microsoft Learn-style repository convention and makes diagrams easy to find and maintain.
