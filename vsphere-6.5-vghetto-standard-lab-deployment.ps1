# Author: William Lam
# Website: www.virtuallyghetto.com
# Description: PowerCLI script to deploy a fully functional vSphere 6.5 lab consisting of 3
#               Nested ESXi hosts enable w/vSAN + VCSA 6.5. Expects a single physical ESXi host
#               as the endpoint and all four VMs will be deployed to physical ESXi host
# Reference: http://www.virtuallyghetto.com/2016/11/vghetto-automated-vsphere-lab-deployment-for-vsphere-6-0u2-vsphere-6-5.html
# Credit: Thanks to Alan Renouf as I borrowed some of his PCLI code snippets :)
#
# Changelog
# 11/22/16
#   * Automatically handle Nested ESXi on vSAN
# 01/20/17
#   * Resolved "Another task in progress" thanks to Jason M
# 02/12/17
#   * Support for deploying to VC Target
#   * Support for enabling SSH on VCSA
#   * Added option to auto-create vApp Container for VMs
#   * Added pre-check for required files
# 02/17/17
#   * Added missing dvFilter param to eth1 (missing in Nested ESXi OVA)
# 02/21/17
#   * Support for deploying NSX 6.3 & registering with vCenter Server
#   * Support for updating Nested ESXi VM to ESXi 6.5a (required for NSX 6.3)
#   * Support for VDS + VXLAN VMkernel configuration (required for NSX 6.3)
#   * Support for "Private" Portgroup on eth1 for Nested ESXi VM used for VXLAN traffic (required for NSX 6.3)
#   * Support for both Virtual & Distributed Portgroup on $VMNetwork
#   * Support for adding ESXi hosts into VC using DNS name (disabled by default)
#   * Added CPU/MEM/Storage resource requirements in confirmation screen

# Physical ESXi host or vCenter Server to deploy vSphere 6.5 lab
$VIServer = "vcenter.primp-industries.com"
$VIUsername = "administrator@vsphere.local"
$VIPassword = "!!!MySuperDuperSecurePassword!!!"

# Specifies whether deployment is to an ESXi host or vCenter Server
# Use either ESXI or VCENTER
$DeploymentTarget = "VCENTER"

# Full Path to both the Nested ESXi 6.5 VA + extracted VCSA 6.5 ISO
$NestedESXiApplianceOVA = "C:\Users\primp\Desktop\Nested_ESXi6.5_Appliance_Template_v1.ova"
$VCSAInstallerPath = "C:\Users\primp\Desktop\VMware-VCSA-all-6.5.0-4944578"
$NSXOVA =  "C:\Users\primp\Desktop\VMware-NSX-Manager-6.3.0-5007049.ova"
$ESXi65aOfflineBundle = "C:\Users\primp\Desktop\ESXi650-201701001\vmw-ESXi-6.5.0-metadata.zip"

# Nested ESXi VMs to deploy
$NestedESXiHostnameToIPs = @{
"vesxi65-1" = "172.30.0.171"
"vesxi65-2" = "172.30.0.172"
"vesxi65-3" = "172.30.0.173"
}

# Nested ESXi VM Resources
$NestedESXivCPU = "2"
$NestedESXivMEM = "6" #GB
$NestedESXiCachingvDisk = "4" #GB
$NestedESXiCapacityvDisk = "8" #GB

# VCSA Deployment Configuration
$VCSADeploymentSize = "tiny"
$VCSADisplayName = "vcenter65-1"
$VCSAIPAddress = "172.30.0.170"
$VCSAHostname = "vcenter65-1.primp-industries.com" #Change to IP if you don't have valid DNS
$VCSAPrefix = "24"
$VCSASSODomainName = "vghetto.local"
$VCSASSOSiteName = "virtuallyGhetto"
$VCSASSOPassword = "VMware1!"
$VCSARootPassword = "VMware1!"
$VCSASSHEnable = "true"

# General Deployment Configuration for Nested ESXi, VCSA & NSX VMs
$VirtualSwitchType = "VDS" # VSS or VDS
$VMNetwork = "dv-access333-dev"
$VMDatastore = "himalaya-local-SATA-dc3500-3"
$VMNetmask = "255.255.255.0"
$VMGateway = "172.30.0.1"
$VMDNS = "172.30.0.100"
$VMNTP = "pool.ntp.org"
$VMPassword = "vmware123"
$VMDomain = "primp-industries.com"
$VMSyslog = "172.30.0.170"
# Applicable to Nested ESXi only
$VMSSH = "true"
$VMVMFS = "false"
# Applicable to VC Deployment Target only
$VMCluster = "Primp-Cluster"

# Name of new vSphere Datacenter/Cluster when VCSA is deployed
$NewVCDatacenterName = "Datacenter"
$NewVCVSANClusterName = "VSAN-Cluster"

# NSX Manager Configuration
$DeployNSX = 0
$NSXvCPU = "2" # Reconfigure NSX vCPU
$NSXvMEM = "8" # Reconfigure NSX vMEM (GB)
$NSXDisplayName = "nsx63-1"
$NSXHostname = "nsx63-1.primp-industries.com"
$NSXIPAddress = "172.30.0.250"
$NSXNetmask = "255.255.255.0"
$NSXGateway = "172.30.0.1"
$NSXSSHEnable = "true"
$NSXCEIPEnable = "false"
$NSXUIPassword = "VMw@re123!"
$NSXCLIPassword = "VMw@re123!"

# VDS / VXLAN Configurations
$PrivateVXLANVMNetwork = "dv-private-network" # Existing Portgroup
$VDSName = "VDS-6.5"
$VXLANDVPortgroup = "VXLAN"
$VXLANSubnet = "172.16.66."
$VXLANNetmask = "255.255.255.0"

# Advanced Configurations
# Set to 1 only if you have DNS (forward/reverse) for ESXi hostnames
$addHostByDnsName = 0
# Upgrade vESXi hosts to 6.5a
$upgradeESXiTo65a = 0

#### DO NOT EDIT BEYOND HERE ####

$verboseLogFile = "vsphere65-vghetto-lab-deployment.log"
$vSphereVersion = "6.5"
$deploymentType = "Standard"
$random_string = -join ((65..90) + (97..122) | Get-Random -Count 8 | % {[char]$_})
$VAppName = "vGhetto-Nested-vSphere-Lab-$vSphereVersion-$random_string"

$vcsaSize2MemoryStorageMap = @{
"tiny"=@{"cpu"="2";"mem"="10";"disk"="250"};
"small"=@{"cpu"="4";"mem"="16";"disk"="290"};
"medium"=@{"cpu"="8";"mem"="24";"disk"="425"};
"large"=@{"cpu"="16";"mem"="32";"disk"="640"};
"xlarge"=@{"cpu"="24";"mem"="48";"disk"="980"}
}

$esxiTotalCPU = 0
$vcsaTotalCPU = 0
$nsxTotalCPU = 0
$esxiTotalMemory = 0
$vcsaTotalMemory = 0
$nsxTotalMemory = 0
$esxiTotStorage = 0
$vcsaTotalStorage = 0
$nsxTotalStorage = 0

$preCheck = 1
$confirmDeployment = 1
$deployNestedESXiVMs = 1
$deployVCSA = 1
$setupNewVC = 1
$addESXiHostsToVC = 1
$configureVSANDiskGroups = 1
$clearVSANHealthCheckAlarm = 1
$setupVXLAN = 1
$configureNSX = 1
$moveVMsIntovApp = 1

$StartTime = Get-Date

Function My-Logger {
    param(
    [Parameter(Mandatory=$true)]
    [String]$message
    )

    $timeStamp = Get-Date -Format "MM-dd-yyyy_hh:mm:ss"

    Write-Host -NoNewline -ForegroundColor White "[$timestamp]"
    Write-Host -ForegroundColor Green " $message"
    $logMessage = "[$timeStamp] $message"
    $logMessage | Out-File -Append -LiteralPath $verboseLogFile
}

if($preCheck -eq 1) {
    if(!(Test-Path $NestedESXiApplianceOVA)) {
        Write-Host -ForegroundColor Red "`nUnable to find $NestedESXiApplianceOVA ...`nexiting"
        exit
    }

    if(!(Test-Path $VCSAInstallerPath)) {
        Write-Host -ForegroundColor Red "`nUnable to find $VCSAInstallerPath ...`nexiting"
        exit
    }

    if($DeployNSX -eq 1) {
        if(!(Test-Path $NSXOVA)) {
            Write-Host -ForegroundColor Red "`nUnable to find $NSXOVA ...`nexiting"
            exit
        }

        if(-not (Get-Module -Name "PowerNSX")) {
            Write-Host -ForegroundColor Red "`nPowerNSX Module is not loaded, please install and load PowerNSX before running script ...`nexiting"
            exit
        }
        $upgradeESXiTo65a = 1
    }

    if($upgradeESXiTo65a -eq 1) {
         if(!(Test-Path $ESXi65aOfflineBundle)) {
            Write-Host -ForegroundColor Red "`nUnable to find $ESXi65aOfflineBundle ...`nexiting"
            exit
        }
    }
}

if($confirmDeployment -eq 1) {
    Write-Host -ForegroundColor Magenta "`nPlease confirm the following configuration will be deployed:`n"

    Write-Host -ForegroundColor Yellow "---- vGhetto vSphere Automated Lab Deployment Configuration ---- "
    Write-Host -NoNewline -ForegroundColor Green "Deployment Target: "
    Write-Host -ForegroundColor White $DeploymentTarget
    Write-Host -NoNewline -ForegroundColor Green "Deployment Type: "
    Write-Host -ForegroundColor White $deploymentType
    Write-Host -NoNewline -ForegroundColor Green "vSphere Version: "
    Write-Host -ForegroundColor White  "vSphere $vSphereVersion"
    Write-Host -NoNewline -ForegroundColor Green "Nested ESXi Image Path: "
    Write-Host -ForegroundColor White $NestedESXiApplianceOVA
    Write-Host -NoNewline -ForegroundColor Green "VCSA Image Path: "
    Write-Host -ForegroundColor White $VCSAInstallerPath

    if($DeployNSX -eq 1) {
        Write-Host -NoNewline -ForegroundColor Green "NSX Image Path: "
        Write-Host -ForegroundColor White $NSXOVA
    }

    if($upgradeESXiTo65a -eq 1) {
        Write-Host -NoNewline -ForegroundColor Green "Extracted ESXi 6.5a Offline Patch Bundle Path: "
        Write-Host -ForegroundColor White $ESXi65aOfflineBundle
    }

    if($DeploymentTarget -eq "ESXI") {
        Write-Host -ForegroundColor Yellow "`n---- Physical ESXi Deployment Target Configuration ----"
        Write-Host -NoNewline -ForegroundColor Green "ESXi Address: "
    } else {
        Write-Host -ForegroundColor Yellow "`n---- vCenter Server Deployment Target Configuration ----"
        Write-Host -NoNewline -ForegroundColor Green "vCenter Server Address: "
    }

    Write-Host -ForegroundColor White $VIServer
    Write-Host -NoNewline -ForegroundColor Green "Username: "
    Write-Host -ForegroundColor White $VIUsername
    Write-Host -NoNewline -ForegroundColor Green "VM Network: "
    Write-Host -ForegroundColor White $VMNetwork

    if($DeployNSX -eq 1 -and $setupVXLAN -eq 1) {
        Write-Host -NoNewline -ForegroundColor Green "Private VXLAN VM Network: "
        Write-Host -ForegroundColor White $PrivateVXLANVMNetwork
    }

    Write-Host -NoNewline -ForegroundColor Green "VM Storage: "
    Write-Host -ForegroundColor White $VMDatastore

    if($DeploymentTarget -eq "VCENTER") {
        Write-Host -NoNewline -ForegroundColor Green "VM Cluster: "
        Write-Host -ForegroundColor White $VMCluster
        Write-Host -NoNewline -ForegroundColor Green "VM vApp: "
        Write-Host -ForegroundColor White $VAppName
    }

    Write-Host -ForegroundColor Yellow "`n---- vESXi Configuration ----"
    Write-Host -NoNewline -ForegroundColor Green "# of Nested ESXi VMs: "
    Write-Host -ForegroundColor White $NestedESXiHostnameToIPs.count
    Write-Host -NoNewline -ForegroundColor Green "vCPU: "
    Write-Host -ForegroundColor White $NestedESXivCPU
    Write-Host -NoNewline -ForegroundColor Green "vMEM: "
    Write-Host -ForegroundColor White "$NestedESXivMEM GB"
    Write-Host -NoNewline -ForegroundColor Green "Caching VMDK: "
    Write-Host -ForegroundColor White "$NestedESXiCachingvDisk GB"
    Write-Host -NoNewline -ForegroundColor Green "Capacity VMDK: "
    Write-Host -ForegroundColor White "$NestedESXiCapacityvDisk GB"
    Write-Host -NoNewline -ForegroundColor Green "IP Address(s): "
    Write-Host -ForegroundColor White $NestedESXiHostnameToIPs.Values
    Write-Host -NoNewline -ForegroundColor Green "Netmask "
    Write-Host -ForegroundColor White $VMNetmask
    Write-Host -NoNewline -ForegroundColor Green "Gateway: "
    Write-Host -ForegroundColor White $VMGateway
    Write-Host -NoNewline -ForegroundColor Green "DNS: "
    Write-Host -ForegroundColor White $VMDNS
    Write-Host -NoNewline -ForegroundColor Green "NTP: "
    Write-Host -ForegroundColor White $VMNTP
    Write-Host -NoNewline -ForegroundColor Green "Syslog: "
    Write-Host -ForegroundColor White $VMSyslog
    Write-Host -NoNewline -ForegroundColor Green "Enable SSH: "
    Write-Host -ForegroundColor White $VMSSH
    Write-Host -NoNewline -ForegroundColor Green "Create VMFS Volume: "
    Write-Host -ForegroundColor White $VMVMFS
    Write-Host -NoNewline -ForegroundColor Green "Root Password: "
    Write-Host -ForegroundColor White $VMPassword

    Write-Host -ForegroundColor Yellow "`n---- VCSA Configuration ----"
    Write-Host -NoNewline -ForegroundColor Green "Deployment Size: "
    Write-Host -ForegroundColor White $VCSADeploymentSize
    Write-Host -NoNewline -ForegroundColor Green "SSO Domain: "
    Write-Host -ForegroundColor White $VCSASSODomainName
    Write-Host -NoNewline -ForegroundColor Green "SSO Site: "
    Write-Host -ForegroundColor White $VCSASSOSiteName
    Write-Host -NoNewline -ForegroundColor Green "SSO Password: "
    Write-Host -ForegroundColor White $VCSASSOPassword
    Write-Host -NoNewline -ForegroundColor Green "Root Password: "
    Write-Host -ForegroundColor White $VCSARootPassword
    Write-Host -NoNewline -ForegroundColor Green "Enable SSH: "
    Write-Host -ForegroundColor White $VCSASSHEnable
    Write-Host -NoNewline -ForegroundColor Green "Hostname: "
    Write-Host -ForegroundColor White $VCSAHostname
    Write-Host -NoNewline -ForegroundColor Green "IP Address: "
    Write-Host -ForegroundColor White $VCSAIPAddress
    Write-Host -NoNewline -ForegroundColor Green "Netmask "
    Write-Host -ForegroundColor White $VMNetmask
    Write-Host -NoNewline -ForegroundColor Green "Gateway: "
    Write-Host -ForegroundColor White $VMGateway

    if($DeployNSX -eq 1 -and $setupVXLAN -eq 1) {
        Write-Host -NoNewline -ForegroundColor Green "VDS Name: "
        Write-Host -ForegroundColor White $VDSName
        Write-Host -NoNewline -ForegroundColor Green "VXLAN Portgroup Name: "
        Write-Host -ForegroundColor White $VXLANDVPortgroup
        Write-Host -NoNewline -ForegroundColor Green "VXLAN Subnet: "
        Write-Host -ForegroundColor White $VXLANSubnet
        Write-Host -NoNewline -ForegroundColor Green "VXLAN Netmask: "
        Write-Host -ForegroundColor White $VXLANNetmask
    }

    if($DeployNSX -eq 1) {
        Write-Host -ForegroundColor Yellow "`n---- NSX Configuration ----"
        Write-Host -NoNewline -ForegroundColor Green "vCPU: "
        Write-Host -ForegroundColor White $NSXvCPU
        Write-Host -NoNewline -ForegroundColor Green "Memory (GB): "
        Write-Host -ForegroundColor White $NSXvMEM
        Write-Host -NoNewline -ForegroundColor Green "Hostname: "
        Write-Host -ForegroundColor White $NSXHostname
        Write-Host -NoNewline -ForegroundColor Green "IP Address: "
        Write-Host -ForegroundColor White $NSXIPAddress
        Write-Host -NoNewline -ForegroundColor Green "Netmask: "
        Write-Host -ForegroundColor White $NSXNetmask
        Write-Host -NoNewline -ForegroundColor Green "Gateway: "
        Write-Host -ForegroundColor White $NSXGateway
        Write-Host -NoNewline -ForegroundColor Green "Enable SSH: "
        Write-Host -ForegroundColor White $NSXSSHEnable
        Write-Host -NoNewline -ForegroundColor Green "Enable CEIP: "
        Write-Host -ForegroundColor White $NSXCEIPEnable
        Write-Host -NoNewline -ForegroundColor Green "UI Password: "
        Write-Host -ForegroundColor White $NSXUIPassword
        Write-Host -NoNewline -ForegroundColor Green "CLI Password: "
        Write-Host -ForegroundColor White $NSXCLIPassword
    }

    $esxiTotalCPU = $NestedESXiHostnameToIPs.count * [int]$NestedESXivCPU
    $esxiTotalMemory = $NestedESXiHostnameToIPs.count * [int]$NestedESXivMEM
    $esxiTotalStorage = ($NestedESXiHostnameToIPs.count * [int]$NestedESXiCachingvDisk) + ($NestedESXiHostnameToIPs.count * [int]$NestedESXiCapacityvDisk)
    $vcsaTotalCPU = $vcsaSize2MemoryStorageMap.$VCSADeploymentSize.cpu
    $vcsaTotalMemory = $vcsaSize2MemoryStorageMap.$VCSADeploymentSize.mem
    $vcsaTotalStorage = $vcsaSize2MemoryStorageMap.$VCSADeploymentSize.disk

    Write-Host -ForegroundColor Yellow "`n---- Resource Requirements ----"
    Write-Host -NoNewline -ForegroundColor Green "ESXi VM CPU: "
    Write-Host -NoNewline -ForegroundColor White $esxiTotalCPU
    Write-Host -NoNewline -ForegroundColor Green " ESXi VM Memory: "
    Write-Host -NoNewline -ForegroundColor White $esxiTotalMemory "GB "
    Write-Host -NoNewline -ForegroundColor Green "ESXi VM Storage: "
    Write-Host -ForegroundColor White $esxiTotalStorage "GB"
    Write-Host -NoNewline -ForegroundColor Green "VCSA VM CPU: "
    Write-Host -NoNewline -ForegroundColor White $vcsaTotalCPU
    Write-Host -NoNewline -ForegroundColor Green " VCSA VM Memory: "
    Write-Host -NoNewline -ForegroundColor White $vcsaTotalMemory "GB "
    Write-Host -NoNewline -ForegroundColor Green "VCSA VM Storage: "
    Write-Host -ForegroundColor White $vcsaTotalStorage "GB"

    if($DeployNSX -eq 1) {
        $nsxTotalCPU = [int]$NSXvCPU
        $nsxTotalMemory = [int]$NSXvMEM
        $nsxTotalStorage = 60
        Write-Host -NoNewline -ForegroundColor Green "NSX  VM CPU: "
        Write-Host -NoNewline -ForegroundColor White $nsxTotalCPU
        Write-Host -NoNewline -ForegroundColor Green " NSX  VM Memory: "
        Write-Host -NoNewline -ForegroundColor White $nsxTotalMemory "GB "
        Write-Host -NoNewline -ForegroundColor Green " NSX  VM Storage: "
        Write-Host -ForegroundColor White $nsxTotalStorage "GB"
    }

    Write-Host -ForegroundColor White "---------------------------------------------"
    Write-Host -NoNewline -ForegroundColor Green "Total CPU: "
    Write-Host -ForegroundColor White ($esxiTotalCPU + $vcsaTotalCPU + $nsxTotalCPU)
    Write-Host -NoNewline -ForegroundColor Green "Total Memory: "
    Write-Host -ForegroundColor White ($esxiTotalMemory + $vcsaTotalMemory + $nsxTotalMemory) "GB"
    Write-Host -NoNewline -ForegroundColor Green "Total Storage: "
    Write-Host -ForegroundColor White ($esxiTotalStorage + $vcsaTotalStorage + $nsxTotalStorage) "GB"

    Write-Host -ForegroundColor Magenta "`nWould you like to proceed with this deployment?`n"
    $answer = Read-Host -Prompt "Do you accept (Y or N)"
    if($answer -ne "Y" -or $answer -ne "y") {
        exit
    }
    Clear-Host
}

My-Logger "Connecting to $VIServer ..."
$viConnection = Connect-VIServer $VIServer -User $VIUsername -Password $VIPassword -WarningAction SilentlyContinue

if($DeploymentTarget -eq "ESXI") {
    $datastore = Get-Datastore -Server $viConnection -Name $VMDatastore
    if($VirtualSwitchType -eq "VSS") {
        $network = Get-VirtualPortGroup -Server $viConnection -Name $VMNetwork
        if($DeployNSX -eq 1) {
            $privateNetwork = Get-VirtualPortGroup -Server $viConnection -Name $PrivateVXLANVMNetwork
        }
    } else {
        $network = Get-VDPortgroup -Server $viConnection -Name $VMNetwork
        if($DeployNSX -eq 1) {
            $privateNetwork = Get-VDPortgroup -Server $viConnection -Name $PrivateVXLANVMNetwork
        }
    }
    $vmhost = Get-VMHost -Server $viConnection

    if($datastore.Type -eq "vsan") {
        My-Logger "VSAN Datastore detected, enabling Fake SCSI Reservations ..."
        Get-AdvancedSetting -Entity $vmhost -Name "VSAN.FakeSCSIReservations" | Set-AdvancedSetting -Value 1 -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
    }
} else {
    $datastore = Get-Datastore -Server $viConnection -Name $VMDatastore | Select -First 1
    if($VirtualSwitchType -eq "VSS") {
        $network = Get-VirtualPortGroup -Server $viConnection -Name $VMNetwork | Select -First 1
        if($DeployNSX -eq 1) {
            $privateNetwork = Get-VirtualPortGroup -Server $viConnection -Name $PrivateVXLANVMNetwork | Select -First 1
        }
    } else {
        $network = Get-VDPortgroup -Server $viConnection -Name $VMNetwork | Select -First 1
        if($DeployNSX -eq 1) {
            $privateNetwork = Get-VDPortgroup -Server $viConnection -Name $PrivateVXLANVMNetwork | Select -First 1
        }
    }
    $cluster = Get-Cluster -Server $viConnection -Name $VMCluster
    $datacenter = $cluster | Get-Datacenter
    $vmhost = $cluster | Get-VMHost | Select -First 1

    if($datastore.Type -eq "vsan") {
        My-Logger "VSAN Datastore detected, enabling Fake SCSI Reservations ..."
        Get-AdvancedSetting -Entity $vmhost -Name "VSAN.FakeSCSIReservations" | Set-AdvancedSetting -Value 1 -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
    }
}

if($deployNestedESXiVMs -eq 1) {
    if($DeploymentTarget -eq "ESXI") {
        $NestedESXiHostnameToIPs.GetEnumerator() | Sort-Object -Property Value | Foreach-Object {
            $VMName = $_.Key
            $VMIPAddress = $_.Value

            My-Logger "Deploying Nested ESXi VM $VMName ..."
            $vm = Import-VApp -Server $viConnection -Source $NestedESXiApplianceOVA -Name $VMName -VMHost $vmhost -Datastore $datastore -DiskStorageFormat thin

            My-Logger "Updating VM Network ..."
            $vm | Get-NetworkAdapter -Name "Network adapter 1" | Set-NetworkAdapter -Portgroup $network -confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
            sleep 5

            if($DeployNSX -eq 1) {
                $vm | Get-NetworkAdapter -Name "Network adapter 2" | Set-NetworkAdapter -Portgroup $privateNetwork -confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
            } else {
                $vm | Get-NetworkAdapter -Name "Network adapter 2" | Set-NetworkAdapter -Portgroup $network -confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
            }

            My-Logger "Updating vCPU Count to $NestedESXivCPU & vMEM to $NestedESXivMEM GB ..."
            Set-VM -Server $viConnection -VM $vm -NumCpu $NestedESXivCPU -MemoryGB $NestedESXivMEM -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

            My-Logger "Updating vSAN Caching VMDK size to $NestedESXiCachingvDisk GB ..."
            Get-HardDisk -Server $viConnection -VM $vm -Name "Hard disk 2" | Set-HardDisk -CapacityGB $NestedESXiCachingvDisk -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

            My-Logger "Updating vSAN Capacity VMDK size to $NestedESXiCapacityvDisk GB ..."
            Get-HardDisk -Server $viConnection -VM $vm -Name "Hard disk 3" | Set-HardDisk -CapacityGB $NestedESXiCapacityvDisk -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

            $orignalExtraConfig = $vm.ExtensionData.Config.ExtraConfig
            $a = New-Object VMware.Vim.OptionValue
            $a.key = "guestinfo.hostname"
            $a.value = $VMName
            $b = New-Object VMware.Vim.OptionValue
            $b.key = "guestinfo.ipaddress"
            $b.value = $VMIPAddress
            $c = New-Object VMware.Vim.OptionValue
            $c.key = "guestinfo.netmask"
            $c.value = $VMNetmask
            $d = New-Object VMware.Vim.OptionValue
            $d.key = "guestinfo.gateway"
            $d.value = $VMGateway
            $e = New-Object VMware.Vim.OptionValue
            $e.key = "guestinfo.dns"
            $e.value = $VMDNS
            $f = New-Object VMware.Vim.OptionValue
            $f.key = "guestinfo.domain"
            $f.value = $VMDomain
            $g = New-Object VMware.Vim.OptionValue
            $g.key = "guestinfo.ntp"
            $g.value = $VMNTP
            $h = New-Object VMware.Vim.OptionValue
            $h.key = "guestinfo.syslog"
            $h.value = $VMSyslog
            $i = New-Object VMware.Vim.OptionValue
            $i.key = "guestinfo.password"
            $i.value = $VMPassword
            $j = New-Object VMware.Vim.OptionValue
            $j.key = "guestinfo.ssh"
            $j.value = $VMSSH
            $k = New-Object VMware.Vim.OptionValue
            $k.key = "guestinfo.createvmfs"
            $k.value = $VMVMFS
            $l = New-Object VMware.Vim.OptionValue
            $l.key = "ethernet1.filter4.name"
            $l.value = "dvfilter-maclearn"
            $m = New-Object VMware.Vim.OptionValue
            $m.key = "ethernet1.filter4.onFailure"
            $m.value = "failOpen"
            $orignalExtraConfig+=$a
            $orignalExtraConfig+=$b
            $orignalExtraConfig+=$c
            $orignalExtraConfig+=$d
            $orignalExtraConfig+=$e
            $orignalExtraConfig+=$f
            $orignalExtraConfig+=$g
            $orignalExtraConfig+=$h
            $orignalExtraConfig+=$i
            $orignalExtraConfig+=$j
            $orignalExtraConfig+=$k
            $orignalExtraConfig+=$l
            $orignalExtraConfig+=$m

            $spec = New-Object VMware.Vim.VirtualMachineConfigSpec
            $spec.ExtraConfig = $orignalExtraConfig

            My-Logger "Adding guestinfo customization properties to $vmname ..."
            $task = $vm.ExtensionData.ReconfigVM_Task($spec)
            $task1 = Get-Task -Id ("Task-$($task.value)")
            $task1 | Wait-Task | Out-Null

            My-Logger "Powering On $vmname ..."
            Start-VM -Server $viConnection -VM $vm -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
        }
    } else {
        $NestedESXiHostnameToIPs.GetEnumerator() | Sort-Object -Property Value | Foreach-Object {
            $VMName = $_.Key
            $VMIPAddress = $_.Value

            $ovfconfig = Get-OvfConfiguration $NestedESXiApplianceOVA
            $ovfconfig.NetworkMapping.VM_Network.value = $VMNetwork

            $ovfconfig.common.guestinfo.hostname.value = $VMName
            $ovfconfig.common.guestinfo.ipaddress.value = $VMIPAddress
            $ovfconfig.common.guestinfo.netmask.value = $VMNetmask
            $ovfconfig.common.guestinfo.gateway.value = $VMGateway
            $ovfconfig.common.guestinfo.dns.value = $VMDNS
            $ovfconfig.common.guestinfo.domain.value = $VMDomain
            $ovfconfig.common.guestinfo.ntp.value = $VMNTP
            $ovfconfig.common.guestinfo.syslog.value = $VMSyslog
            $ovfconfig.common.guestinfo.password.value = $VMPassword
            if($VMSSH -eq "true") {
                $VMSSHVar = $true
            } else {
                $VMSSHVar = $false
            }
            $ovfconfig.common.guestinfo.ssh.value = $VMSSHVar

            My-Logger "Deploying Nested ESXi VM $VMName ..."
            $vm = Import-VApp -Source $NestedESXiApplianceOVA -OvfConfiguration $ovfconfig -Name $VMName -Location $cluster -VMHost $vmhost -Datastore $datastore -DiskStorageFormat thin

            # Add the dvfilter settings to the exisiting ethernet1 (not part of ova template)
            My-Logger "Correcting missing dvFilter settings for Eth1 ..."
            $vm | New-AdvancedSetting -name "ethernet1.filter4.name" -value "dvfilter-maclearn" -confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
            $vm | New-AdvancedSetting -Name "ethernet1.filter4.onFailure" -value "failOpen" -confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

            if($DeployNSX -eq 1) {
                My-Logger "Connecting Eth1 to $privateNetwork ..."
                $vm | Get-NetworkAdapter -Name "Network adapter 2" | Set-NetworkAdapter -Portgroup $privateNetwork -confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
            }

            My-Logger "Updating vCPU Count to $NestedESXivCPU & vMEM to $NestedESXivMEM GB ..."
            Set-VM -Server $viConnection -VM $vm -NumCpu $NestedESXivCPU -MemoryGB $NestedESXivMEM -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

            My-Logger "Updating vSAN Caching VMDK size to $NestedESXiCachingvDisk GB ..."
            Get-HardDisk -Server $viConnection -VM $vm -Name "Hard disk 2" | Set-HardDisk -CapacityGB $NestedESXiCachingvDisk -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

            My-Logger "Updating vSAN Capacity VMDK size to $NestedESXiCapacityvDisk GB ..."
            Get-HardDisk -Server $viConnection -VM $vm -Name "Hard disk 3" | Set-HardDisk -CapacityGB $NestedESXiCapacityvDisk -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

            My-Logger "Powering On $vmname ..."
            $vm | Start-Vm -RunAsync | Out-Null
        }
    }
}

if($DeployNSX -eq 1) {
    if($DeploymentTarget -eq "VCENTER") {
        $ovfconfig = Get-OvfConfiguration $NSXOVA
        $ovfconfig.NetworkMapping.VSMgmt.value = $VMNetwork

        $ovfconfig.common.vsm_hostname.value = $NSXHostname
        $ovfconfig.common.vsm_ip_0.value = $NSXIPAddress
        $ovfconfig.common.vsm_netmask_0.value = $NSXNetmask
        $ovfconfig.common.vsm_gateway_0.value = $NSXGateway
        $ovfconfig.common.vsm_dns1_0.value = $VMDNS
        $ovfconfig.common.vsm_domain_0.value = $VMDomain
        if($NSXSSHEnable -eq "true") {
            $NSXSSHEnableVar = $true
        } else {
            $NSXSSHEnableVar = $false
        }
        $ovfconfig.common.vsm_isSSHEnabled.value = $NSXSSHEnableVar
        if($NSXCEIPEnable -eq "true") {
            $NSXCEIPEnableVar = $true
        } else {
            $NSXCEIPEnableVar = $false
        }
        $ovfconfig.common.vsm_isCEIPEnabled.value = $NSXCEIPEnableVar
        $ovfconfig.common.vsm_cli_passwd_0.value = $NSXUIPassword
        $ovfconfig.common.vsm_cli_en_passwd_0.value = $NSXCLIPassword

        My-Logger "Deploying NSX VM $NSXDisplayName ..."
        $vm = Import-VApp -Source $NSXOVA -OvfConfiguration $ovfconfig -Name $NSXDisplayName -Location $cluster -VMHost $vmhost -Datastore $datastore -DiskStorageFormat thin

        My-Logger "Updating vCPU Count to $NSXvCPU & vMEM to $NSXvMEM GB ..."
        Set-VM -Server $viConnection -VM $vm -NumCpu $NSXvCPU -MemoryGB $NSXvMEM -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

        My-Logger "Powering On $NSXDisplayName ..."
        $vm | Start-Vm -RunAsync | Out-Null
    }
}

if($upgradeESXiTo65a -eq 1) {
    $NestedESXiHostnameToIPs.GetEnumerator() | sort -Property Value | Foreach-Object {
        $VMName = $_.Key
        $VMIPAddress = $_.Value

        My-Logger "Connecting directly to $VMName for ESXi upgrade ..."
        $vESXi = Connect-VIServer -Server $VMIPAddress -User root -Password $VMPassword -WarningAction SilentlyContinue

        My-Logger "Entering Maintenance Mode ..."
        Set-VMHost -VMhost $VMIPAddress -State Maintenance -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

        My-Logger "Upgrading $VMName to ESXi 6.5a ..."
        Install-VMHostPatch -VMHost $VMIPAddress -LocalPath $ESXi65aOfflineBundle -HostUsername root -HostPassword $VMPassword -WarningAction SilentlyContinue -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

        My-Logger "Rebooting $VMName ..."
        Restart-VMHost $VMIPAddress -RunAsync -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

        My-Logger "Disconnecting from new ESXi host ..."
        Disconnect-VIServer $vESXi -Confirm:$false
    }
}

if($deployVCSA -eq 1) {
    if($DeploymentTarget -eq "ESXI") {
        # Deploy using the VCSA CLI Installer
        $config = (Get-Content -Raw "$($VCSAInstallerPath)\vcsa-cli-installer\templates\install\embedded_vCSA_on_ESXi.json") | convertfrom-json
        $config.'new.vcsa'.esxi.hostname = $VIServer
        $config.'new.vcsa'.esxi.username = $VIUsername
        $config.'new.vcsa'.esxi.password = $VIPassword
        $config.'new.vcsa'.esxi.'deployment.network' = $VMNetwork
        $config.'new.vcsa'.esxi.datastore = $datastore
        $config.'new.vcsa'.appliance.'thin.disk.mode' = $true
        $config.'new.vcsa'.appliance.'deployment.option' = $VCSADeploymentSize
        $config.'new.vcsa'.appliance.name = $VCSADisplayName
        $config.'new.vcsa'.network.'ip.family' = "ipv4"
        $config.'new.vcsa'.network.mode = "static"
        $config.'new.vcsa'.network.ip = $VCSAIPAddress
        $config.'new.vcsa'.network.'dns.servers'[0] = $VMDNS
        $config.'new.vcsa'.network.prefix = $VCSAPrefix
        $config.'new.vcsa'.network.gateway = $VMGateway
        $config.'new.vcsa'.network.'system.name' = $VCSAHostname
        $config.'new.vcsa'.os.password = $VCSARootPassword
        if($VCSASSHEnable -eq "true") {
            $VCSASSHEnableVar = $true
        } else {
            $VCSASSHEnableVar = $false
        }
        $config.'new.vcsa'.os.'ssh.enable' = $VCSASSHEnableVar
        $config.'new.vcsa'.sso.password = $VCSASSOPassword
        $config.'new.vcsa'.sso.'domain-name' = $VCSASSODomainName
        $config.'new.vcsa'.sso.'site-name' = $VCSASSOSiteName

        My-Logger "Creating VCSA JSON Configuration file for deployment ..."
        $config | ConvertTo-Json | Set-Content -Path "$($ENV:Temp)\jsontemplate.json"

        My-Logger "Deploying the VCSA ..."
        Invoke-Expression "$($VCSAInstallerPath)\vcsa-cli-installer\win32\vcsa-deploy.exe install --no-esx-ssl-verify --accept-eula --acknowledge-ceip $($ENV:Temp)\jsontemplate.json"| Out-File -Append -LiteralPath $verboseLogFile
    } else {
        $config = (Get-Content -Raw "$($VCSAInstallerPath)\vcsa-cli-installer\templates\install\embedded_vCSA_on_VC.json") | convertfrom-json
        $config.'new.vcsa'.vc.hostname = $VIServer
        $config.'new.vcsa'.vc.username = $VIUsername
        $config.'new.vcsa'.vc.password = $VIPassword
        $config.'new.vcsa'.vc.'deployment.network' = $VMNetwork
        $config.'new.vcsa'.vc.datastore = $datastore
        $config.'new.vcsa'.vc.datacenter = $datacenter.name
        $config.'new.vcsa'.vc.target = $VMCluster
        $config.'new.vcsa'.appliance.'thin.disk.mode' = $true
        $config.'new.vcsa'.appliance.'deployment.option' = $VCSADeploymentSize
        $config.'new.vcsa'.appliance.name = $VCSADisplayName
        $config.'new.vcsa'.network.'ip.family' = "ipv4"
        $config.'new.vcsa'.network.mode = "static"
        $config.'new.vcsa'.network.ip = $VCSAIPAddress
        $config.'new.vcsa'.network.'dns.servers'[0] = $VMDNS
        $config.'new.vcsa'.network.prefix = $VCSAPrefix
        $config.'new.vcsa'.network.gateway = $VMGateway
        $config.'new.vcsa'.network.'system.name' = $VCSAHostname
        $config.'new.vcsa'.os.password = $VCSARootPassword
        if($VCSASSHEnable -eq "true") {
            $VCSASSHEnableVar = $true
        } else {
            $VCSASSHEnableVar = $false
        }
        $config.'new.vcsa'.os.'ssh.enable' = $VCSASSHEnableVar
        $config.'new.vcsa'.sso.password = $VCSASSOPassword
        $config.'new.vcsa'.sso.'domain-name' = $VCSASSODomainName
        $config.'new.vcsa'.sso.'site-name' = $VCSASSOSiteName

        My-Logger "Creating VCSA JSON Configuration file for deployment ..."
        $config | ConvertTo-Json | Set-Content -Path "$($ENV:Temp)\jsontemplate.json"

        My-Logger "Deploying the VCSA ..."
        Invoke-Expression "$($VCSAInstallerPath)\vcsa-cli-installer\win32\vcsa-deploy.exe install --no-esx-ssl-verify --accept-eula --acknowledge-ceip $($ENV:Temp)\jsontemplate.json"| Out-File -Append -LiteralPath $verboseLogFile
    }
}

if($moveVMsIntovApp -eq 1 -and $DeploymentTarget -eq "VCENTER") {
    My-Logger "Creating vApp $VAppName ..."
    $VApp = New-VApp -Name $VAppName -Server $viConnection -Location $cluster

    if($deployNestedESXiVMs -eq 1) {
        My-Logger "Moving Nested ESXi VMs into $VAppName vApp ..."
        $NestedESXiHostnameToIPs.GetEnumerator() | Sort-Object -Property Value | Foreach-Object {
            $vm = Get-VM -Name $_.Key -Server $viConnection
            Move-VM -VM $vm -Server $viConnection -Destination $VApp -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
        }
    }

    if($deployVCSA -eq 1) {
        $vcsaVM = Get-VM -Name $VCSADisplayName -Server $viConnection
        My-Logger "Moving $VCSADisplayName into $VAppName vApp ..."
        Move-VM -VM $vcsaVM -Server $viConnection -Destination $VApp -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
    }

    if($DeployNSX -eq 1) {
        $nsxVM = Get-VM -Name $NSXDisplayName -Server $viConnection
        My-Logger "Moving $NSXDisplayName into $VAppName vApp ..."
        Move-VM -VM $nsxVM -Server $viConnection -Destination $VApp -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
    }
}

My-Logger "Disconnecting from $VIServer ..."
Disconnect-VIServer $viConnection -Confirm:$false


if($setupNewVC -eq 1) {
    My-Logger "Connecting to the new VCSA ..."
    $vc = Connect-VIServer $VCSAIPAddress -User "administrator@$VCSASSODomainName" -Password $VCSASSOPassword -WarningAction SilentlyContinue

    My-Logger "Creating Datacenter $NewVCDatacenterName ..."
    New-Datacenter -Server $vc -Name $NewVCDatacenterName -Location (Get-Folder -Type Datacenter -Server $vc) | Out-File -Append -LiteralPath $verboseLogFile

    My-Logger "Creating VSAN Cluster $NewVCVSANClusterName ..."
    New-Cluster -Server $vc -Name $NewVCVSANClusterName -Location (Get-Datacenter -Name $NewVCDatacenterName -Server $vc) -DrsEnabled -VsanEnabled -VsanDiskClaimMode 'Manual' | Out-File -Append -LiteralPath $verboseLogFile

    if($addESXiHostsToVC -eq 1) {
        $NestedESXiHostnameToIPs.GetEnumerator() | sort -Property Value | Foreach-Object {
            $VMName = $_.Key
            $VMIPAddress = $_.Value

            $targetVMHost = $VMIPAddress
            if($addHostByDnsName -eq 1) {
                $targetVMHost = $VMName
            }
            My-Logger "Adding ESXi host $targetVMHost to Cluster ..."
            Add-VMHost -Server $vc -Location (Get-Cluster -Name $NewVCVSANClusterName) -User "root" -Password $VMPassword -Name $targetVMHost -Force | Out-File -Append -LiteralPath $verboseLogFile
        }
    }

    if($DeployNSX -eq 1 -and $setupVXLAN -eq 1) {
        My-Logger "Creating VDS $VDSName ..."
        $vds = New-VDSwitch -Server $vc -Name $VDSName -Location (Get-Datacenter -Name $NewVCDatacenterName)

        My-Logger "Creating new VXLAN DVPortgroup $VXLANDVPortgroup ..."
        $vxlanDVPG = New-VDPortgroup -Server $vc -Name $VXLANDVPortgroup -Vds $vds

        $vmhosts = Get-Cluster -Server $vc -Name $NewVCVSANClusterName | Get-VMHost
        foreach ($vmhost in $vmhosts) {
            $vmhostname = $vmhost.name

            My-Logger "Adding $vmhostname to VDS ..."
            Add-VDSwitchVMHost -Server $vc -VDSwitch $vds -VMHost $vmhost | Out-File -Append -LiteralPath $verboseLogFile

            My-Logger "Adding vmmnic1 to VDS ..."
            $vmnic = $vmhost | Get-VMHostNetworkAdapter -Physical -Name vmnic1
            Add-VDSwitchPhysicalNetworkAdapter -Server $vc -DistributedSwitch $vds -VMHostPhysicalNic $vmnic -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

            $vmk0 = Get-VMHostNetworkAdapter -Server $vc -Name vmk0 -VMHost $vmhost
            $lastNetworkOcet = $vmk0.ip.Split('.')[-1]
            $vxlanVmkIP = $VXLANSubnet + $lastNetworkOcet

            My-Logger "Adding VXLAN VMKernel $vxlanVmkIP to VDS ..."
            New-VMHostNetworkAdapter -VMHost $vmhost -PortGroup $VXLANDVPortgroup -VirtualSwitch $vds -IP $vxlanVmkIP -SubnetMask $VXLANNetmask -Mtu 1600 | Out-File -Append -LiteralPath $verboseLogFile
       }
    }

    if($configureVSANDiskGroups -eq 1) {
        My-Logger "Enabling VSAN Space Efficiency/De-Dupe & disabling VSAN Health Check ..."
        Get-VsanClusterConfiguration -Server $vc -Cluster $NewVCVSANClusterName | Set-VsanClusterConfiguration -SpaceEfficiencyEnabled $true -HealthCheckIntervalMinutes 0 | Out-File -Append -LiteralPath $verboseLogFile


        foreach ($vmhost in Get-Cluster -Server $vc | Get-VMHost) {
            $luns = $vmhost | Get-ScsiLun | select CanonicalName, CapacityGB

            My-Logger "Querying ESXi host disks to create VSAN Diskgroups ..."
            foreach ($lun in $luns) {
                if(([int]($lun.CapacityGB)).toString() -eq "$NestedESXiCachingvDisk") {
                    $vsanCacheDisk = $lun.CanonicalName
                }
                if(([int]($lun.CapacityGB)).toString() -eq "$NestedESXiCapacityvDisk") {
                    $vsanCapacityDisk = $lun.CanonicalName
                }
            }
            My-Logger "Creating VSAN DiskGroup for $vmhost ..."
            New-VsanDiskGroup -Server $vc -VMHost $vmhost -SsdCanonicalName $vsanCacheDisk -DataDiskCanonicalName $vsanCapacityDisk | Out-File -Append -LiteralPath $verboseLogFile
          }
    }

    if($clearVSANHealthCheckAlarm -eq 1) {
        My-Logger "Clearing default VSAN Health Check Alarms, not applicable in Nested ESXi env ..."
        $alarmMgr = Get-View AlarmManager -Server $vc
        Get-Cluster -Server $vc | where {$_.ExtensionData.TriggeredAlarmState} | %{
            $cluster = $_
            $Cluster.ExtensionData.TriggeredAlarmState | %{
                $alarmMgr.AcknowledgeAlarm($_.Alarm,$cluster.ExtensionData.MoRef)
            }
        }
    }

    # Exit maintanence mode in case patching was done earlier
    foreach ($vmhost in Get-Cluster -Server $vc | Get-VMHost) {
        if($vmhost.ConnectionState -eq "Maintenance") {
            Set-VMHost -VMhost $vmhost -State Connected -RunAsync -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
        }
    }

    My-Logger "Disconnecting from new VCSA ..."
    Disconnect-VIServer $vc -Confirm:$false
}

if($configureNSX -eq 1 -and $DeployNSX -eq 1 -and $setupVXLAN -eq 1) {
    if(!(Connect-NSXServer -Server $NSXHostname -Username admin -Password $NSXUIPassword -DisableVIAutoConnect -WarningAction SilentlyContinue)) {
        Write-Host -ForegroundColor Red "Unable to connect to NSX Manager, please check the deployment"
        exit
    } else {
        My-Logger "Successfully logged into NSX Manager $NSXHostname ..."
    }

    $ssoUsername = "administrator@$VCSASSODomainName"
    My-Logger "Registering NSX Manager with vCenter Server $VCSAHostname ..."
    $vcConfig = Set-NsxManager -vCenterServer $VCSAHostname -vCenterUserName $ssoUsername -vCenterPassword $VCSASSOPassword

    My-Logger "Registering NSX Manager with vCenter SSO $VCSAHostname ..."
    $ssoConfig = Set-NsxManager -SsoServer $VCSAHostname -SsoUserName $ssoUsername -SsoPassword $VCSASSOPassword -AcceptAnyThumbprint

    My-Logger "Disconnecting from NSX Manager ..."
    Disconnect-NsxServer
}

$EndTime = Get-Date
$duration = [math]::Round((New-TimeSpan -Start $StartTime -End $EndTime).TotalMinutes,2)

My-Logger "vSphere $vSphereVersion Lab Deployment Complete!"
My-Logger "StartTime: $StartTime"
My-Logger "  EndTime: $EndTime"
My-Logger " Duration: $duration minutes"