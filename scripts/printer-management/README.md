# 🖨️ Printer Management Scripts

A comprehensive suite of PowerShell scripts for deploying, monitoring, and troubleshooting network printers. These tools help system administrators manage print infrastructure efficiently, from initial deployment to ongoing maintenance and issue resolution.

## 📁 Scripts in This Directory

| Script | Description |
|--------|-------------|
| `Printer-Deployment.ps1` | Install, configure, and manage network printers |
| `Printer-HealthCheck.ps1` | Monitor printer status, queues, and performance |
| `Printer-Troubleshooting.ps1` | Diagnose and repair common printer issues |

---

## 🚀 Quick Start

```powershell
# Load all printer management scripts
. .\Printer-Deployment.ps1
. .\Printer-HealthCheck.ps1
. .\Printer-Troubleshooting.ps1

# Install a network printer
Install-NetworkPrinter -PrinterName "HP-Floor2" -PortIP "192.168.1.100" -Shared

# Check printer health
Get-PrinterStatus -PrinterName "HP-Floor2"

# Troubleshoot a problematic printer
Start-PrinterTroubleshooter -PrinterName "HP-Floor2"
