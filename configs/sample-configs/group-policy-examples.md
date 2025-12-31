# Group Policy Object (GPO) Gold Standards

**Scope:** Active Directory Domain Joined Devices
**Strategy:** "Least Privilege" & "Defense in Depth"

---

## 1. Security Baselines (Computer Configuration)
*Apply to: All Workstations / Servers*

### A. Local Account Security (Prevent Lateral Movement)
**Path:** `Computer Config > Policies > Windows Settings > Security Settings > Local Policies > Security Options`

* **Network security: LAN Manager authentication level:** `Send NTLMv2 response only. Refuse LM & NTLM` (Kills NTLMv1/Relay attacks).
* **Accounts: Rename guest account:** `[Random Name]`
* **Interactive logon: Machine inactivity limit:** `900 seconds` (15 mins).
* **User Account Control (UAC):** `Always notify`.

### B. Microsoft LAPS (Local Administrator Password Solution)
*Crucial:* Never use the same local admin password across the fleet.
**Path:** `Computer Config > Policies > Administrative Templates > LAPS`

* **Enable local admin password management:** `Enabled`
* **Password Settings:** Length `16`, Age `30 days`.

### C. Ransomware Protections (Software Restriction)
**Path:** `Computer Config > Policies > Windows Settings > Security Settings > Software Restriction Policies`

* **Block Executables in AppData:** Create a path rule disallowing `*.exe` in `%AppData%`. (Stops simple droppers).
* **Disable Macros:** (Ideally done via Office ADMX templates) -> "Block macros from running in Office files from the Internet".

---

## 2. User Experience (User Configuration)
*Apply to: Domain Users*

### A. Drive Maps
**Path:** `User Config > Preferences > Windows Settings > Drive Maps`

* **Action:** `Replace` (Ensures if map is deleted, it comes back).
* **Location:** `\\fileserver\department` mapped to `S:`.
* **Item-level Targeting:** Target specific Security Groups (e.g., `HR-Users`).

### B. Browser Standardization (Edge/Chrome)
**Path:** `User Config > Policies > Admin Templates > Microsoft Edge`

* **Home Page:** `https://intranet.company.com`
* **Force Install Extensions:** Install uBlock Origin or Password Manager automatically.
* **Password Manager:** `Disable` (Force use of Enterprise Password Manager).

---

## 3. Auditing (The "Black Box")
**Path:** `Computer Config > Policies > Windows Settings > Security Settings > Advanced Audit Policy`

* **Account Logon:** `Success and Failure`
* **Object Access:** `Failure` (Detect unauthorized file access).
* **Process Creation:** `Success` (Log every `.exe` launched - critical for forensics).
