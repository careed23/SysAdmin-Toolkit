# VoIP & SIP Troubleshooting Standard Operating Procedure (SOP)

**Version:** 1.0
**Last Updated:** [Date]
**Scope:** Diagnosis and resolution of Voice over IP (VoIP) call quality and connectivity issues.

---

## 1. Quick Diagnostic Matrix

Use this table to correlate user complaints with technical root causes.

| Symptom | Description | Most Likely Cause |
| :--- | :--- | :--- |
| **One-Way Audio** | You hear them, they can't hear you (or vice versa). | **SIP ALG** enabled on firewall, or NAT traversal issue. |
| **Choppy / Robot Voice** | Voice cuts in and out or sounds synthesized. | **Packet Loss** (>1%) or High **Jitter** (>30ms). |
| **Dropped Calls** | Call disconnects at exactly 30 seconds or 15 minutes. | **UDP Timeout** misconfiguration or SIP Keep-Alive failure. |
| **Echo** | User hears their own voice returned. | Acoustic feedback (volume too high) or high latency (>150ms). |
| **Registration Failed** | Phone cannot connect to PBX. | Firewall blocking Port 5060, wrong credentials, or DNS failure. |

---

## 2. The Golden Rule: SIP ALG

**SIP ALG (Application Layer Gateway)** is the #1 cause of VoIP issues. It attempts to inspect and rewrite SIP packets but often corrupts the header, causing one-way audio or dropped calls.

### Action Plan:
1.  **Disable SIP ALG** on the edge router/firewall immediately.
2.  **Verify:** Check the router's connection tracking table to ensure SIP packets are passing without modification.

---

## 3. Network Performance Requirements

VoIP is UDP-based and real-time; it cannot tolerate valid TCP retransmissions. The network must meet these thresholds:

* **Latency (Ping):** Must be **< 150ms** (round-trip time).
* **Jitter:** Must be **< 30ms** (variance in packet arrival time).
* **Packet Loss:** Must be **< 1%** (ideally 0%).
* **Bandwidth:** Allocate approx. **100kbps** per active concurrent call (up/down).

---

## 4. CLI Diagnostic Tools

Do not guess. Use these tools to gather data.

### A. Network Path Analysis (MTR)
Use `mtr` (My Traceroute) to see where packet loss occurs along the path to the VoIP provider.
```bash
# Usage: mtr -rwc 100 [VoIP_Provider_IP]
# Example:
mtr -rwc 100 sip.ringcentral.com
Look for sudden spikes in the "Loss%" column at a specific hop.

B. Connectivity Check (Netcat)
Telnet does not support UDP. Use nc to verify port connectivity through the firewall.

Bash

# Check SIP Signaling (Port 5060 UDP)
nc -z -v -u [VoIP_Provider_IP] 5060
C. Packet Capture (Tcpdump)
If you need to prove the ISP is dropping audio, capture the traffic on the gateway.

Bash

# Capture traffic for a specific phone IP
sudo tcpdump -i eth0 host 192.168.1.50 -w voip_capture.pcap
Review the .pcap file in Wireshark. Go to Telephony > VoIP Calls to visualize the flow.

5. Router & Firewall Configuration Checklist
[ ] UDP Timeout: Increase UDP connection timeout to 300 seconds (standard is often 30s, causing dropped calls).

[ ] QoS (Quality of Service): Ensure VoIP traffic is prioritized (High Priority/Real-time).

[ ] DSCP Tagging: Ensure traffic is tagged EF (Expedited Forwarding) or 46.

[ ] VLAN: Isolate phones on a dedicated Voice VLAN (e.g., VLAN 20) to separate them from heavy data traffic (YouTube, downloads).

6. Escalation Data
If contacting the ISP or VoIP Provider, provide:

Source IP (Phone) and Destination IP (PBX).

Time stamps of 3 failed calls (in UTC).

The MTR report showing network path quality.


---

### Risk vs. Reward

* **Risk:** Low. These are diagnostic steps. The only configuration change suggested is disabling SIP ALG and adjusting timeouts, which are industry standards.
* **Reward:** High. VoIP issues are often "ghosts" that plague IT departments for months. This guide forces a structured approach that identifies the root cause (usually the ISP or the Router) within minutes, protecting your time and reputation.

### Next Step

You now have the complete text for the VoIP troubleshooting guide.
**Would you like me to generate the final `init_repo.sh` script now?** This will take all
