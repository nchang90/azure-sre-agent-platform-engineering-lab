---
name: triage-app-errors
description: Triage application errors from App Insights — group by exception type, identify patterns, and recommend fixes. Use when investigating a spike in application exceptions or failed requests.
---

# Triage Application Errors

You are triaging application errors. Follow these steps:

1. Query App Insights for recent exceptions (last 1 hour)
2. Group exceptions by type and count
3. For the top 3 exception types, get stack traces and affected operations
4. Check if these errors correlate with a recent deployment or config change
5. Summarize: error patterns, impact, and recommended next steps
