access_key                  = ""
ami_name                    = "w2022-2108-dc-dx-en_{{timestamp}}"
ami_description             = "AMI for #{node[:platform]} #{node[:platform_version]}"
ami_virtualization_type     = "hvm"
ami_users                   = []
ami_groups                  = []
ami_org_arns                = []
ami_ou_arns                 = []
ami_product_codes           = []
ami_regions                 = []
associate_public_ip_address = false
assume_role                 = {}
availability_zone           = ""
check_registry              = true
communicator                = "winrm"
debug_mode                  = 1
disable_stop_instance       = false
ebs_optimized               = false
elevated_password           = ""
elevated_user               = ""
ena_support                 = false
encrypt_boot                = true
execution_policy            = "unrestricted"
filters = [
  "exclude:$_.Title -like '*Preview*'",
  "include:$true",
]
force_deregister      = false
force_delete_snapshot = false
iam_instance_profile  = ""
instance_type         = "m5.large"
kms_key_id            = ""
//launch_block_device_mappings = {}
max_retries        = 0
pause_before       = "10s"
pause_before_ssm   = "10s"
region             = "eu-central-1"
region_kms_key_ids = {}
restart_command    = ""
restart_timeout    = "5m"
search_criteria    = "IsInstalled=0"
secret_key         = ""
// security_group_filter = {}
security_group_id          = ""
security_group_ids         = []
skip_clean                 = false
skip_credential_validation = false
skip_profile_validation    = false
skip_region_validation     = false
skip_save_build_region     = false
shared_credentials_file    = ""
shutdown_timeout           = "1h"
snapshot_tags              = {}
snapshot_users             = []
snapshot_groups            = []
source_ami                 = "ami-0e9c4fcadaf9f4a63"
//source_ami_filter    = {}
start_retry_timeout = "5m"
//subnet_filter        =   ""
subnet_id = ""
tags = {
  "Name"      = "w2022-2108-dc-core-en-{{timestamp}}",
  "Owner"     = "xoap",
  "CreatedAt" = "{{timestamp}}",
}
//temporary_iam_instance_profile_policy_document =
timeout        = "1h"
update_limit   = 100
user_data      = ""
user_data_file = "./boot_config/winrm_bootstrap.txt"
valid_exit_codes = [
  "0",
  "4294967295"
]
//vault_aws_engine = {}
winrm_insecure = true
winrm_timeout  = "2h"
winrm_use_ntlm = false
winrm_use_ssl  = true
winrm_username = "Administrator"
