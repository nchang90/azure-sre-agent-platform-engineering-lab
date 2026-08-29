# Knowledge Base

Central repository for runbooks, architecture docs, and incident guides.

## 📋 Incident Runbooks
See [runbooks/](runbooks/) for actionable runbooks organized by service area:
- **Containers**: HTTP 5xx errors, Container Apps issues
- **Front Door**: Routing rules, health probes, origin failures
- **AKS**: Node pool issues, pod scheduling, network problems
- **Monitoring**: Log Analytics queries, alert tuning

## 🏗️ Architecture
- [Orders API Architecture](runbooks/containers/orders-architecture.md) - System design, data flow, dependencies

## 📞 On-Call & Incident Ops
- [On-Call Handoff](on-call-handoff.md) - Shift change checklist and knowledge transfer
- [Incident Report Template](incident-report.md) - Post-incident review structure
- [GitHub Issue Triage](github-issue-triage.md) - Classification and routing

## 🔗 How to Use
1. **Incident happens** → Find relevant [runbook](runbooks/)
2. **Diagnose** → Run KQL queries, check logs
3. **Remediate** → Follow remediation steps
4. **Post-incident** → Fill [incident report](incident-report.md)
5. **Handoff** → Use [on-call template](on-call-handoff.md)

## ✍️ Contributing
New runbook? See [runbooks/README.md](runbooks/README.md).

---

**Last updated:** 2026-08-29
