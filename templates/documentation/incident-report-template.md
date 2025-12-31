# Incident Report

---

## Document Control

| Field | Value |
|-------|-------|
| **Incident ID** | INC-2024-XXXX |
| **Report Version** | 1.0 |
| **Classification** | ☐ Public ☐ Internal ☐ Confidential ☐ Restricted |
| **Status** | ☐ Draft ☐ Under Review ☐ Approved ☐ Final |
| **Created Date** | YYYY-MM-DD |
| **Last Updated** | YYYY-MM-DD |
| **Author** | [Name, Title] |
| **Reviewed By** | [Name, Title] |
| **Approved By** | [Name, Title] |

---

## Executive Summary

> **Brief Description:** [One paragraph summary of the incident, impact, and resolution]

| Metric | Value |
|--------|-------|
| **Incident Type** | ☐ Security ☐ Outage ☐ Performance ☐ Data Loss ☐ Hardware ☐ Software ☐ Network ☐ Other |
| **Severity Level** | ☐ Critical (P1) ☐ High (P2) ☐ Medium (P3) ☐ Low (P4) |
| **Total Duration** | XX hours XX minutes |
| **Users Affected** | XXX users / XX% of user base |
| **Systems Affected** | [List primary systems] |
| **Financial Impact** | $XXX,XXX (estimated) |
| **Data Breach** | ☐ Yes ☐ No ☐ Under Investigation |
| **Root Cause** | [Brief statement] |
| **Resolution** | [Brief statement] |

---

## 1. Incident Overview

### 1.1 Incident Classification

| Category | Selection |
|----------|-----------|
| **Primary Category** | ☐ Availability ☐ Integrity ☐ Confidentiality ☐ Performance |
| **Secondary Category** | [If applicable] |
| **Incident Type** | ☐ Unplanned Outage ☐ Security Breach ☐ Data Corruption ☐ Service Degradation ☐ Unauthorized Access ☐ Malware ☐ Phishing ☐ DDoS ☐ Configuration Error ☐ Hardware Failure ☐ Software Bug ☐ Capacity Issue ☐ Third-Party Failure ☐ Natural Disaster ☐ Human Error ☐ Other: _______ |

### 1.2 Severity Matrix

| Level | Criteria | This Incident |
|-------|----------|---------------|
| **Critical (P1)** | Complete service outage, security breach with data exfiltration, >50% users affected | ☐ |
| **High (P2)** | Major functionality impaired, potential security risk, 25-50% users affected | ☐ |
| **Medium (P3)** | Partial service degradation, workaround available, 10-25% users affected | ☐ |
| **Low (P4)** | Minor issue, minimal impact, <10% users affected | ☐ |

### 1.3 Key Dates and Times

| Event | Date | Time (UTC) | Time (Local) |
|-------|------|------------|--------------|
| **Incident Start** | YYYY-MM-DD | HH:MM | HH:MM TZ |
| **Incident Detected** | YYYY-MM-DD | HH:MM | HH:MM TZ |
| **Incident Declared** | YYYY-MM-DD | HH:MM | HH:MM TZ |
| **First Response** | YYYY-MM-DD | HH:MM | HH:MM TZ |
| **Escalation (if any)** | YYYY-MM-DD | HH:MM | HH:MM TZ |
| **Mitigation Started** | YYYY-MM-DD | HH:MM | HH:MM TZ |
| **Service Restored** | YYYY-MM-DD | HH:MM | HH:MM TZ |
| **Incident Closed** | YYYY-MM-DD | HH:MM | HH:MM TZ |

**Key Metrics:**
- **Time to Detect (TTD):** XX minutes
- **Time to Respond (TTR):** XX minutes
- **Time to Mitigate (TTM):** XX hours XX minutes
- **Time to Resolve (MTTR):** XX hours XX minutes
- **Total Downtime:** XX hours XX minutes

---

## 2. Impact Assessment

### 2.1 Business Impact

| Impact Area | Description | Severity |
|-------------|-------------|----------|
| **Revenue** | [Describe revenue impact] | ☐ None ☐ Low ☐ Medium ☐ High ☐ Critical |
| **Operations** | [Describe operational impact] | ☐ None ☐ Low ☐ Medium ☐ High ☐ Critical |
| **Reputation** | [Describe reputational impact] | ☐ None ☐ Low ☐ Medium ☐ High ☐ Critical |
| **Compliance** | [Describe compliance/regulatory impact] | ☐ None ☐ Low ☐ Medium ☐ High ☐ Critical |
| **Customer Trust** | [Describe customer impact] | ☐ None ☐ Low ☐ Medium ☐ High ☐ Critical |

### 2.2 Technical Impact

| System/Service | Impact Level | Description |
|----------------|--------------|-------------|
| [System 1] | ☐ Down ☐ Degraded ☐ Unaffected | [Details] |
| [System 2] | ☐ Down ☐ Degraded ☐ Unaffected | [Details] |
| [System 3] | ☐ Down ☐ Degraded ☐ Unaffected | [Details] |
| [Database] | ☐ Down ☐ Degraded ☐ Unaffected | [Details] |
| [Network] | ☐ Down ☐ Degraded ☐ Unaffected | [Details] |

### 2.3 User Impact

| User Group | Number Affected | Impact Description |
|------------|-----------------|-------------------|
| Internal Employees | XXX | [Description] |
| External Customers | XXX | [Description] |
| Partners/Vendors | XXX | [Description] |
| Executive Staff | XXX | [Description] |

### 2.4 Geographic Impact

| Location/Region | Affected | Impact Level |
|-----------------|----------|--------------|
| Headquarters | ☐ Yes ☐ No | [Level] |
| Branch Offices | ☐ Yes ☐ No | [Level] |
| Remote Workers | ☐ Yes ☐ No | [Level] |
| Cloud Services | ☐ Yes ☐ No | [Level] |
| [Region 1] | ☐ Yes ☐ No | [Level] |
| [Region 2] | ☐ Yes ☐ No | [Level] |

### 2.5 Data Impact

| Question | Response | Details |
|----------|----------|---------|
| Was data accessed without authorization? | ☐ Yes ☐ No ☐ Unknown | |
| Was data modified or corrupted? | ☐ Yes ☐ No ☐ Unknown | |
| Was data exfiltrated? | ☐ Yes ☐ No ☐ Unknown | |
| Was data destroyed or deleted? | ☐ Yes ☐ No ☐ Unknown | |
| Personal data involved (PII/PHI)? | ☐ Yes ☐ No ☐ Unknown | |
| Financial data involved? | ☐ Yes ☐ No ☐ Unknown | |
| Intellectual property involved? | ☐ Yes ☐ No ☐ Unknown | |

**Data Classification Affected:**
- ☐ Public
- ☐ Internal
- ☐ Confidential
- ☐ Restricted/Highly Confidential

**Estimated Records Affected:** [Number]

---

## 3. Incident Timeline

### 3.1 Detailed Chronology

| Date/Time (UTC) | Event | Actor/System | Details |
|-----------------|-------|--------------|---------|
| YYYY-MM-DD HH:MM | Initial trigger/cause | [System/Person] | [Detailed description] |
| YYYY-MM-DD HH:MM | First symptoms observed | [System/Person] | [Detailed description] |
| YYYY-MM-DD HH:MM | Alert generated | [Monitoring system] | [Alert details] |
| YYYY-MM-DD HH:MM | On-call notified | [Name] | [Notification method] |
| YYYY-MM-DD HH:MM | Initial investigation started | [Team/Person] | [Actions taken] |
| YYYY-MM-DD HH:MM | Incident declared | [Name] | [Severity assigned] |
| YYYY-MM-DD HH:MM | Incident Commander assigned | [Name] | [Communication started] |
| YYYY-MM-DD HH:MM | Escalation to [team/vendor] | [Name] | [Reason for escalation] |
| YYYY-MM-DD HH:MM | Root cause identified | [Team/Person] | [Description] |
| YYYY-MM-DD HH:MM | Mitigation action taken | [Team/Person] | [Action description] |
| YYYY-MM-DD HH:MM | Service partially restored | [Team/Person] | [What was restored] |
| YYYY-MM-DD HH:MM | Service fully restored | [Team/Person] | [Confirmation details] |
| YYYY-MM-DD HH:MM | Monitoring confirmed stable | [System/Person] | [Metrics observed] |
| YYYY-MM-DD HH:MM | Incident closed | [Name] | [Closure criteria met] |

### 3.2 Timeline Visualization
