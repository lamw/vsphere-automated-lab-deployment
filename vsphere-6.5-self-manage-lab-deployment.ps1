# Author: William Lam
# Website: www.virtuallyghetto.com
# Description: PowerCLI script to deploy a fully functional vSphere 6.5 lab consisting of 3
#               Nested ESXi hosts enable w/vSAN + VCSA 6.5. Expects a single physical ESXi host
#               as the endpoint and all three Nested ESXi VMs will be deployed to physical ESXi host
#               with the VCSA then being deployed to the inner-Nested ESXi VMs as a self-managed VC
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

# Nested ESXi VMs to deploy
$NestedESXiHostnameToIPs = @{
"vesxi65-1" = "172.30.0.171"
"vesxi65-2" = "172.30.0.172"
"vesxi65-3" = "172.30.0.173"
}

#Nested ESXi Bootstrap Node
$bootStrapNode = "172.30.0.171"

# Nested ESXi VM Resources
$NestedESXivCPU = "2"
$NestedESXivMEM = "32" #GB
$NestedESXiCachingvDisk = "16" #GB
$NestedESXiCapacityvDisk = "200" #GB

# VCSA Deployment Configuration
$VCSADeploymentSize = "tiny"
$VCSADisplayName = "vcenter65-1"
$VCSAIPAddress = "172.30.0.170"
$VCSAHostname = "vcenter65-1.primp-industries.com" #Change to IP if you don't have valid DNS
$VCSAPrefix = "24"
$VCSASSODomainName = "vsphere.local"
$VCSASSOSiteName = "virtuallyGhetto"
$VCSASSOPassword = "VMware1!"
$VCSARootPassword = "VMware1!"
$VCSASSHEnable = "true"

# General Deployment Configuration for both Nested ESXi VMs + VCSA
$VMNetwork = "access333"
$VMDatastore = "himalaya-local-SATA-dc3500-2"
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

#### DO NOT EDIT BEYOND HERE ####

$verboseLogFile = "vsphere65-lab-deployment.log"
$vSphereVersion = "6.5"
$deploymentType = "Self Managed"
$random_string = -join ((65..90) + (97..122) | Get-Random -Count 8 | % {[char]$_})
$VAppName = "Nested-vSphere-Lab-$vSphereVersion-$random_string"

$preCheck = 1
$confirmDeployment = 1
$deployNestedESXiVMs = 1
$bootStrapFirstNestedESXiVM = 1
$deployVCSA = 1
$setupNewVC = 1
$addESXiHostsToVC = 1
$configureVSANDiskGroups = 1
$clearVSANHealthCheckAlarm = 1
$moveVMsIntovApp = 1

$StartTime = Get-Date

Function My-Logger {
    param(
    [Parameter(Mandatory=$true)]
    [String]$message
    )

    $timeStamp = Get-Date -Format "MM-dd-yyyy_hh-mm-ss"

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
}

if($confirmDeployment -eq 1) {
    Write-Host -ForegroundColor Magenta "`nPlease confirm the following configuration will be deployed:`n"

    Write-Host -ForegroundColor Yellow "---- vSphere Automated Lab Deployment Configuration ---- "
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

    if($DeploymentTarget -eq "ESXI") {
        Write-Host -ForegroundColor Yellow "`n---- Physical ESXi Configuration ----"
        Write-Host -NoNewline -ForegroundColor Green "ESXi Address: "
    } else {
        Write-Host -ForegroundColor Yellow "`n---- vCenter Server Configuration ----"
        Write-Host -NoNewline -ForegroundColor Green "vCenter Server Address: "
    }

    Write-Host -ForegroundColor White $VIServer
    Write-Host -NoNewline -ForegroundColor Green "Username: "
    Write-Host -ForegroundColor White $VIUsername
    Write-Host -NoNewline -ForegroundColor Green "VM Network: "
    Write-Host -ForegroundColor White $VMNetwork
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
    Write-Host -NoNewline -ForegroundColor Green "Bootstrap ESXi Node: "
    Write-Host -ForegroundColor White $bootStrapNode

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

    Write-Host -ForegroundColor Magenta "`nWould you like to proceed with this deployment?`n"
    $answer = Read-Host -Prompt "Do you accept (Y or N)"
    if($answer -ne "Y" -or $answer -ne "y") {
        exit
    }
    Clear-Host
}

if($deployNestedESXiVMs -eq 1) {
    My-Logger "Connecting to $VIServer ..."
    $viConnection = Connect-VIServer $VIServer -User $VIUsername -Password $VIPassword -WarningAction SilentlyContinue

    if($DeploymentTarget -eq "ESXI") {
        $datastore = Get-Datastore -Server $viConnection -Name $VMDatastore
        $vmhost = Get-VMHost -Server $viConnection
        $network = Get-VirtualPortGroup -Server $viConnection -Name $VMNetwork -VMHost $vmhost

        if($datastore.Type -eq "vsan") {
            My-Logger "VSAN Datastore detected, enabling Fake SCSI Reservations ..."
            Get-AdvancedSetting -Entity $vmhost -Name "VSAN.FakeSCSIReservations" | Set-AdvancedSetting -Value 1 -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
        }
    } else {
        $datastore = Get-Datastore -Server $viConnection -Name $VMDatastore | Select -First 1
        $network = Get-VirtualPortGroup -Server $viConnection -Name $VMNetwork | Select -First 1
        $cluster = Get-Cluster -Server $viConnection -Name $VMCluster
        $datacenter = $cluster | Get-Datacenter
        $vmhost = $cluster | Get-VMHost | Select -First 1
    }

    if($DeploymentTarget -eq "ESXI") {
        $NestedESXiHostnameToIPs.GetEnumerator() | Sort-Object -Property Value | Foreach-Object {
            $VMName = $_.Key
            $VMIPAddress = $_.Value

            My-Logger "Deploying Nested ESXi VM $VMName ..."
            $vm = Import-VApp -Server $viConnection -Source $NestedESXiApplianceOVA -Name $VMName -VMHost $vmhost -Datastore $datastore -DiskStorageFormat thin

            My-Logger "Updating VM Network ..."
            foreach($networkAdapter in ($vm | Get-NetworkAdapter))
            {
                My-Logger "Configuring adapter $networkAdapter in $vm"
                $networkAdapter | Set-NetworkAdapter -Portgroup $network -confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
                sleep 5
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
            $task1 | Wait-Task | Out-File -Append -LiteralPath $verboseLogFile

            My-Logger "Powering On $vmname ..."
            Start-VM -Server $viConnection -VM $vm -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
        }
    } else {
        $NestedESXiHostnameToIPs.GetEnumerator() | Sort-Object -Property Value | Foreach-Object {
            $VMName = $_.Key
            $VMIPAddress = $_.Value

            $ovfconfig = Get-OvfConfiguration $NestedESXiApplianceOVA
            $networkMapLabel = ($ovfconfig.ToHashTable().keys | where {$_ -Match "NetworkMapping"}).replace("NetworkMapping.","").replace("-","_").replace(" ","_")
            $ovfconfig.NetworkMapping.$networkMapLabel.value = $VMNetwork

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
            My-Logger "Correcting missing dvFilter settings for Ethernet[1] ..."
            $vm | New-AdvancedSetting -name "ethernet1.filter4.name" -value "dvfilter-maclearn" -confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
            $vm | New-AdvancedSetting -Name "ethernet1.filter4.onFailure" -value "failOpen" -confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

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
 
    if($moveVMsIntovApp -eq 1 -and $DeploymentTarget -eq "VCENTER") {
        # Check whether DRS is enabled as that is required to create vApp
        if((Get-Cluster -Server $viConnection $cluster).DrsEnabled) {
            My-Logger "Creating vApp $VAppName ..."
            $VApp = New-VApp -Name $VAppName -Server $viConnection -Location $cluster

            if($deployNestedESXiVMs -eq 1) {
                My-Logger "Moving Nested ESXi VMs into $VAppName vApp ..."
                $NestedESXiHostnameToIPs.GetEnumerator() | Sort-Object -Property Value | Foreach-Object {
                    $vm = Get-VM -Name $_.Key -Server $viConnection
                    Move-VM -VM $vm -Server $viConnection -Destination $VApp -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
                }
            }
        } else {
            My-Logger "vApp $VAppName will NOT be created as DRS is NOT enabled on vSphere Cluster ${cluster} ..."
        }
    }
 
    My-Logger "Disconnecting from $VIServer ..."
    Disconnect-VIServer $viConnection -Confirm:$false
}

if($bootStrapFirstNestedESXiVM -eq 1) {
    do {
        My-Logger "Waiting for $bootStrapNode to be ready on network ..."
        $ping = test-connection $bootStrapNode -Quiet
        sleep 60
    } until ($ping -contains "True")

    My-Logger "Connecting to ESXi bootstrap node ..."
    $vEsxi = Connect-VIServer -Server $bootStrapNode -User root -Password $VMPassword -WarningAction SilentlyContinue

    My-Logger "Updating the ESXi host VSAN Policy to allow Force Provisioning ..."
    $esxcli = Get-EsxCli -Server $vEsxi -V2
    $VSANPolicy = '(("hostFailuresToTolerate" i1) ("forceProvisioning" i1))'
    $VSANPolicyDefaults = $esxcli.vsan.policy.setdefault.CreateArgs()
    $VSANPolicyDefaults.policy = $VSANPolicy
    $VSANPolicyDefaults.policyclass = "vdisk"
    $esxcli.vsan.policy.setdefault.Invoke($VSANPolicyDefaults) | Out-File -Append -LiteralPath $verboseLogFile
    $VSANPolicyDefaults.policyclass = "vmnamespace"
    $esxcli.vsan.policy.setdefault.Invoke($VSANPolicyDefaults) | Out-File -Append -LiteralPath $verboseLogFile

    My-Logger "Creating a new VSAN Cluster"
    $esxcli.vsan.cluster.new.Invoke() | Out-File -Append -LiteralPath $verboseLogFile

    $luns = Get-ScsiLun -Server $vEsxi | select CanonicalName, CapacityGB

    My-Logger "Querying ESXi host disks to create VSAN Diskgroups ..."
    foreach ($lun in $luns) {
        if(([int]($lun.CapacityGB)).toString() -eq "$NestedESXiCachingvDisk") {
            $vsanCacheDisk = $lun.CanonicalName
        }
        if(([int]($lun.CapacityGB)).toString() -eq "$NestedESXiCapacityvDisk") {
            $vsanCapacityDisk = $lun.CanonicalName
        }
    }

    My-Logger "Tagging Capacity Disk ..."
    $capacitytag = $esxcli.vsan.storage.tag.add.CreateArgs()
    $capacitytag.disk = $vsanCapacityDisk
    $capacitytag.tag = "capacityFlash"
    $esxcli.vsan.storage.tag.add.Invoke($capacitytag) | Out-File -Append -LiteralPath $verboseLogFile

    My-Logger "Creating VSAN Diskgroup ..."
    $addvsanstorage = $esxcli.vsan.storage.add.CreateArgs()
    $addvsanstorage.ssd = $vsanCacheDisk
    $addvsanstorage.disks = $vsanCapacityDisk
    $esxcli.vsan.storage.add.Invoke($addvsanstorage) | Out-File -Append -LiteralPath $verboseLogFile

    My-Logger "Disconnecting from $esxi ..."
    Disconnect-VIServer $vEsxi -Confirm:$false
}

if($deployVCSA -eq 1) {
    My-Logger "Connecting to first ESXi bootstrap node ..."
    $vEsxi = Connect-VIServer -Server $bootStrapNode -User root -Password $VMPassword -WarningAction SilentlyContinue

    # Deploy using the VCSA CLI Installer
    $config = (Get-Content -Raw "$($VCSAInstallerPath)\vcsa-cli-installer\templates\install\embedded_vCSA_on_ESXi.json") | convertfrom-json
    $config.'new.vcsa'.esxi.hostname = $bootStrapNode
    $config.'new.vcsa'.esxi.username = "root"
    $config.'new.vcsa'.esxi.password = $VMPassword
    $config.'new.vcsa'.esxi.'deployment.network' = "VM Network"
    $config.'new.vcsa'.esxi.datastore = "vsanDatastore"
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
    Invoke-Expression "$($VCSAInstallerPath)\vcsa-cli-installer\win32\vcsa-deploy.exe install --no-esx-ssl-verify --accept-eula --acknowledge-ceip $($ENV:Temp)\jsontemplate.json" | Out-File -Append -LiteralPath $verboseLogFile

    My-Logger "Disconnecting from $bootStrapNode ..."
    Disconnect-VIServer $vEsxi -Confirm:$false
}

if($setupNewVC -eq 1) {
    My-Logger "Connecting to the new VCSA ..."
    $vc = Connect-VIServer $VCSAIPAddress -User "administrator@$VCSASSODomainName" -Password $VCSASSOPassword -WarningAction SilentlyContinue

    My-Logger "Creating Datacenter $NewVCDatacenterName ..."
    New-Datacenter -Server $vc -Name $NewVCDatacenterName -Location (Get-Folder -Type Datacenter -Server $vc) | Out-File -Append -LiteralPath $verboseLogFile

    My-Logger "Creating VSAN Cluster $NewVCVSANClusterName ..."
    New-Cluster -Server $vc -Name $NewVCVSANClusterName -Location (Get-Datacenter -Name $NewVCDatacenterName -Server $vc) -DrsEnabled -VsanEnabled -VsanDiskClaimMode 'Manual' | Out-File -Append -LiteralPath $verboseLogFile

    if($addESXiHostsToVC -eq 1) {
        $NestedESXiHostnameToIPs.GetEnumerator() | Sort-Object -Property Value | Foreach-Object {
            $VMName = $_.Key
            $VMIPAddress = $_.Value

            My-Logger "Adding ESXi host $VMIPAddress to Cluster ..."
            Add-VMHost -Server $vc -Location (Get-Cluster -Name $NewVCVSANClusterName) -User "root" -Password $VMPassword -Name $VMIPAddress -Force | Out-File -Append -LiteralPath $verboseLogFile
        }

    }

    if($configureVSANDiskGroups -eq 1) {
        My-Logger "Enabling VSAN Space Efficiency/De-Dupe & disabling VSAN Health Check ..."
        Get-VsanClusterConfiguration -Server $vc -Cluster $NewVCVSANClusterName | Set-VsanClusterConfiguration -SpaceEfficiencyEnabled $true -HealthCheckIntervalMinutes 0 | Out-File -Append -LiteralPath $verboseLogFile

        foreach ($vmhost in Get-Cluster -Server $vc | Get-VMHost) {
            if((Get-VsanDiskGroup -VMHost $vmhost) -eq $null) {
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

        My-Logger "Updating VSAN Default VM Storage Policy back to its defaults ..."
        $VSANPolicy = Get-SpbmStoragePolicy "Virtual SAN Default Storage Policy"
        $Ruleset = New-SpbmRuleSet -Name "Rule-set 1" -AllOfRules @((New-SpbmRule -Capability VSAN.forceProvisioning $false), (New-SpbmRule -Capability VSAN.hostFailuresToTolerate 1))
        $VSANPolicy | Set-SpbmStoragePolicy -RuleSet $Ruleset | Out-File -Append -LiteralPath $verboseLogFile
    }

    My-Logger "Disconnecting from new VCSA ..."
    Disconnect-VIServer $vc -Confirm:$false
}
$EndTime = Get-Date
$duration = [math]::Round((New-TimeSpan -Start $StartTime -End $EndTime).TotalMinutes,2)

My-Logger "vSphere $vSphereVersion Lab Deployment Complete!"
My-Logger "StartTime: $StartTime"
My-Logger "  EndTime: $EndTime"
My-Logger " Duration: $duration minutes"
