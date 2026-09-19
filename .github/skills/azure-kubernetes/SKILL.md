---
name: azure-kubernetes
description: Plan, create, and configure Azure Kubernetes Service (AKS) clusters, including networking, security, observability, reliability, and cost controls.
---

# Azure Kubernetes Service

Use this skill when users ask for AKS cluster planning, provisioning guidance, or AKS platform optimization.

## When to use

- Create a new AKS cluster
- Choose AKS SKU and node pool strategy
- Design AKS networking and ingress/egress
- Configure AKS security and identity
- Set up AKS observability and upgrades
- Optimize AKS performance and cost

## Investigation / planning flow

1. Gather requirements (environment, scale, region, constraints).
2. Separate Day-0 decisions (networking, API exposure, identity) from Day-1 features.
3. Propose a production-safe baseline for reliability, security, and operations.
4. Call out tradeoffs and recommended defaults.
5. Provide rollout and validation checkpoints.

## Guardrails

- Prefer least-risk defaults when requirements are missing.
- Distinguish facts from assumptions.
- Avoid destructive or irreversible actions without explicit approval.
- Do not request or expose secrets.
