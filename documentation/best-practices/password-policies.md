# Corporate Password & Authentication Policy

**Effective Date:** [Date]
**Audience:** All employees, contractors, and automated systems.
**Authority:** IT Security Department

---

## 1. Policy Statement
Passwords are the first line of defense against unauthorized access. This policy moves away from "complexity theater" (forcing symbols/numbers) and focuses on **entropy (length)** and **Multi-Factor Authentication (MFA)**.

## 2. General User Accounts
* **Minimum Length:** 12 characters.
* **Complexity:** No specific character class requirements (e.g., !@#) are enforced if length > 14 characters.
* **Passphrases:** Users are encouraged to use sentences (e.g., `Correct-Horse-Battery-Staple`).
* **Expiration:** Passwords do **NOT** expire automatically. Rotation is forced only upon:
    1.  Indication of compromise.
    2.  User request.
* **History:** Cannot reuse the last 5 passwords.
* **Lockout:** Account locks for 30 minutes after 10 failed attempts.

## 3. Privileged Accounts (Admins)
* **Minimum Length:** 16 characters.
* **Separation of Duties:** Admin accounts must **never** be used for daily tasks (email/web browsing). They are for administration only.
* **MFA:** **Mandatory.** No administrative access is permitted without MFA.
* **Caching:** "Remember Password" features are strictly prohibited for admin credentials.

## 4. Service Accounts (Non-Human)
* **Minimum Length:** 25+ characters (randomly generated).
* **Storage:** Must be stored in a secured Vault (e.g., HashiCorp Vault, Azure KeyVault, KeepassXC).
* **Rotation:** Rotated annually or immediately upon staff departure who had knowledge of the credential.
* **Interactive Logon:** Must be **DISABLED** (GPO: *Deny log on locally*).

## 5. Multi-Factor Authentication (MFA)
MFA is the enforcement layer that makes a stolen password useless.
* **Scope:** Required for:
    * All Remote Access (VPN, RDP Gateway).
    * All Cloud Applications (Microsoft 365, AWS, G-Suite).
    * All Privileged/Admin logins.
* **Approved Methods:**
    1.  Hardware Token (YubiKey).
    2.  Mobile App Authenticator (Google/Microsoft Auth).
* **Prohibited Methods:** SMS/Text Message (due to SIM Swapping vulnerabilities).

## 6. Prohibited Behavior
* **Sharing:** Passwords must never be shared via email, chat, or verbal communication.
* **Reuse:** Corporate passwords must not be used on personal sites (Facebook, LinkedIn).
* **Storage:** Writing passwords on physical media (sticky notes) or unencrypted files is a disciplinary offense.

## 7. Compromise Protocol
If a user suspects their credentials are compromised:
1.  Immediately change the password.
2.  Report the incident to IT Security.
3.  IT will terminate all active sessions and review logs for the past 24 hours.
Risk vs. Reward
Risk: User Friction. Users hate MFA and long passwords. They may complain about "usability." Mitigation: Educate them that using a 4-word sentence is actually easier to type and remember than P@$$w0rd1!.

Reward: Attack Surface Reduction. By eliminating SMS MFA and enforcing length, you neutralize 99% of brute-force attacks and automated credential stuffing.
