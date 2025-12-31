# Backup Strategies & Architectures

**Version:** 1.0
**Purpose:** Technical guidance on backup methods, rotation schemes, and recovery objectives.

---

## 1. Defining Success: RPO vs. RTO
Before configuring a backup job, you must define these two metrics for the specific asset.

| Metric | Definition | Business Impact |
| :--- | :--- | :--- |
| **RPO (Recovery Point Objective)** | Max acceptable data loss measured in time. | "If we crash at 5 PM and restore to 1 PM, is losing 4 hours of data acceptable?" |
| **RTO (Recovery Time Objective)** | Max acceptable downtime. | "How long can the business survive while the server is restoring?" |

**Strategy:**
* **High RPO/RTO (Low Criticality):** Nightly backups are sufficient.
* **Low RPO/RTO (Mission Critical):** Requires snapshots, replication, or Continuous Data Protection (CDP).

---

## 2. Backup Methods Comparison

### A. Full Backup
* **How it works:** Backs up the entire dataset every time.
* **Pros:** Fastest restore (only need one file).
* **Cons:** Slowest backup time; consumes massive storage.
* **Use Case:** Weekly master backups; System State images.

### B. Incremental Backup
* **How it works:** Backs up only data changed since the *last backup* (whether full or incremental).
* **Pros:** Fastest backup window; lowest storage usage.
* **Cons:** Slowest restore (must reassemble Full + Inc 1 + Inc 2 + ... + Inc X).
* **Use Case:** Hourly/Daily backups for file servers.

### C. Differential Backup
* **How it works:** Backs up data changed since the last *Full* backup.
* **Pros:** Faster restore than Incremental (only need Full + latest Diff).
* **Cons:** Backup size grows daily until the next Full.
* **Use Case:** Databases requiring faster restores than incremental allows.

### D. Synthetic Full
* **How it works:** The backup software merges the previous Full and subsequent Incrementals into a new "Full" file on the storage end, without touching the production server.
* **Pros:** Low impact on production; fast restores.
* **Use Case:** Modern virtual machine backups (Veeam, Datto).

---

## 3. Rotation Schemes

### Grandfather-Father-Son (GFS)
The industry standard for balancing retention with storage costs.

* **Son (Daily):** Retain for 7-14 days. (Incremental)
* **Father (Weekly):** Retain for 4-5 weeks. (Full)
* **Grandfather (Monthly):** Retain for 12 months+ (Full/Archival)
* **Great-Grandfather (Yearly):** Retain for 7 years (Compliance/Legal).

---

## 4. The "Air Gap" Strategy
Ransomware actively hunts for backups to encrypt them. You must have an "Air Gap."

**Implementation Options:**
1.  **Physical Tape:** Physically ejected and taken offsite. (The ultimate air gap).
2.  **Immutable Cloud Storage:** AWS S3 Object Lock / Azure Blob Immutability. Data cannot be deleted/modified by *anyone* (even you) for the set duration.
3.  **Offline Disk:** A USB drive plugged in only during the backup window and removed immediately after.

---

## 5. Deduplication & Compression
To make "Zero-Cost" strategies viable, you must minimize storage costs.
* **Source-Side Dedupe:** Removes duplicate blocks *before* sending data over the network. (Saves Bandwidth).
* **Target-Side Dedupe:** Removes duplicates at the storage device. (Saves Disk Space).

**Recommendation:** Enable compression on all log files and text-heavy databases. Expect 2:1 to 4:1 compression ratios.
Risk vs. Reward
Risk: Complexity. Mixing Differential and Incremental strategies can make restores confusing. Mitigation: Stick to Synthetic Fulls (modern standard) or simple GFS if using older tools.

Reward: Audit Confidence. When a client or auditor asks "How far back can we go?", showing them a GFS rotation schedule (Daily, Weekly, Monthly, Yearly) ends the conversation immediately.
