boot_command      = [
  "<enter>"
  ]
boot_wait         = "5s"
check_registry    = true
communicator      = "winrm"
compression_level = "9"
cpus              = 4
debug_mode        = 1
disk_adapter_type = "nvme"
disk_size         = 61440
disk_type_id      = "1"
elevated_password = ""
elevated_user     = ""
execution_policy  = "unrestricted"
floppy_files = [
  "./autounattend.xml",
  "../../../../scripts/packer_windows_server_2025_scripts/01_Cleanup_Temporary_Files.ps1",
  "../../../../scripts/packer_windows_server_2025_scripts/02_Clear_Event_Logs.ps1",
  "../../../../scripts/packer_windows_server_2025_scripts/03_Reset_Windows_Update.ps1",
  "../../../../scripts/packer_windows_server_2025_scripts/04_Disable_Unnecessary_Services.ps1",
  "../../../../scripts/packer_windows_server_2025_scripts/05_Apply_CIS_Benchmarks.ps1",
  "../../../../scripts/packer_windows_server_2025_scripts/06_Enable_Defender_Settings.ps1",
  "../../../../scripts/packer_windows_server_2025_scripts/07_Disable_SMBv1_Legacy.ps1",
  "../../../../scripts/packer_windows_server_2025_scripts/08_Disable_Telemetry.ps1",
  "../../../../scripts/packer_windows_server_2025_scripts/09_Configure_Power_Settings.ps1",
  "../../../../scripts/packer_windows_server_2025_scripts/10_Windows_Update_Policies.ps1",
  "../../../../scripts/packer_windows_server_2025_scripts/11_Generate_Compliance_Report.ps1",
  "../../../../scripts/packer_windows_server_2025_scripts/12_Final_Cleanup_Sysprep.ps1",
  "../../../../scripts/disable-screensaver.ps1",
  "../../../../scripts/configure-winrm.ps1",
  "../../../../scripts/unattend.xml",
  "../../../../scripts/run-sysprep.ps1",
  "../../../../scripts/cleanup.ps1"
]
floppy_dirs = [
  "../../../../scripts/packer_windows_server_2025_scripts/common"
]
filters = [
  "exclude:$_.Title -like '*Preview*'",
  "exclude:$_.Title -like '*Feature update*'",
  "include:$true",
  ]
format               = "vmx"
guest_os_type        = "windows2019srvNext-64"
headless             = "false"
iso_checksum         = "TBD_CHECKSUM_FOR_W2025_ISO"
iso_url              = "../../../../iso/windows_server_2025_standard_x64.iso"
keep_input_artifact  = true
max_retries          = 0
memory               = 4096
network_adapter_type = ""
output_directory     = "./output/w2025-2412-std-core-en"
ovftool_options      = []
pause_before         = "10s"
restart_command      = ""
restart_timeout      = "5m"
search_criteria      = "IsInstalled=0"
skip_clean           = false
skip_compaction      = false
shutdown_command     = "powershell.exe -noexit -file a:/12_Final_Cleanup_Sysprep.ps1"
shutdown_timeout     = "1h"
start_retry_timeout  = "5m"
timeout              = "1h"
tools_upload_flavor  = ""
tools_upload_path    = ""
tools_source_path    = ""
update_limit         = 100
valid_exit_codes     = [
  "0",
  "4294967295"
  ]
vagrant_output_directory       = "./output/vagrant"
vagrant_version                = "0.0.1"
version                        = 21
vm_name                        = "w2025-2412-std-core-en"
vmx_remove_ethernet_interfaces = true
vnc_port_min                   = 5980
vnc_port_max                   = 5990
winrm_insecure                 = true
winrm_password                 = "Password01"
winrm_port                     = "5985"
winrm_timeout                  = "2h"
winrm_use_ntlm                 = false
winrm_use_ssl                  = false
winrm_username                 = "xoap-admin"
