packer {
  required_plugins {
    windows-update = {
      version = "0.14.1"
      source  = "github.com/rgl/windows-update"
    }
  }
}

variable "access_key" {
  description = "The access key used to communicate with AWS. Learn how to set this. On EBS, this is not required if you are using use_vault_aws_engine for authentication instead."
  sensitive   = true
  type        = string
  default     = ""
}

variable "ami_name" {
  description = "TThe name of the resulting AMI that will appear when managing AMIs in the AWS console or via APIs. This must be unique."
  sensitive   = false
  type        = string
  default     = ""
}

variable "ami_description" {
  description = "The description to set for the resulting AMI(s). By default this description is empty."
  sensitive   = false
  type        = string
  default     = ""
}

variable "ami_virtualization_type" {
  description = " The type of virtualization for the AMI you are building. This option is required to register HVM images. Can be paravirtual (default) or hvm."
  sensitive   = false
  type        = string
  default     = "paravirtual"
}

variable "ami_users" {
  description = <<DOC
    A list of groups that have access to launch the resulting AMI(s).
    By default no groups have permission to launch the AMI. all will make the AMI publicly accessible.
    AWS currently doesn't accept any value other than all.
  DOC
  sensitive   = false
  type        = list(string)
  default = [
    "all"
  ]
}

variable "ami_org_arns" {
  description = "A list of Amazon Resource Names (ARN) of AWS Organizations that have access to launch the resulting AMI(s). By default no organizations have permission to launch the AMI."
  sensitive   = false
  type        = list(string)
  default     = []
}

variable "ami_ou_arns" {
  description = <<DOC
    A list of Amazon Resource Names (ARN) of AWS Organizations organizational units (OU) that have access to launch the resulting AMI(s).
    By default no organizational units have permission to launch the AMI.
  DOC
  sensitive   = false
  type        = list(string)
  default     = []
}

variable "ami_groups" {
  description = "A list of groups that have access to launch the resulting AMI(s). By default no additional groups other than the group creating the AMI has permissions to launch it."
  sensitive   = false
  type        = list(string)
  default     = []
}

variable "ami_product_codes" {
  description = "A list of product codes to associate with the AMI. By default no product codes are associated with the AMI."
  sensitive   = false
  type        = list(string)
  default     = []
}

variable "ami_regions" {
  description = "A list of regions to copy the AMI to. Tags and attributes are copied along with the AMI. AMI copying takes time depending on the size of the AMI, but will generally take many minutes."
  sensitive   = false
  type        = list(string)
  default     = []
}

variable "associate_public_ip_address" {
  description = "If using a non-default VPC, public IP addresses are not provided by default. If this is true, your new instance will get a Public IP. default: false"
  sensitive   = true
  type        = bool
  default     = false
}

variable "assume_role" {
  description = "If provided with a role ARN, Packer will attempt to assume this role using the supplied credentials."
  sensitive   = true
  type        = map(string)
  default     = {}
}

variable "availability_zone" {
  description = "Destination availability zone to launch instance in. Leave this empty to allow Amazon to auto-assign."
  sensitive   = false
  type        = string
  default     = ""
}

variable "check_registry" {
  description = <<DOC
    The check_registry is a boolean that determines whether or not to check the registry for the presence of the Windows Update key.
    If true, checks for several registry keys that indicate that the system is going to reboot.
    This is useful if an installation kicks off a reboot and you want the provisioner to wait for that reboot to complete before reconnecting.
    Please note that this option is a beta feature, and we generally recommend that you finish installs that auto-reboot (like Windows Updates)
    during your autounattend phase before the winrm provisioner connects.
  DOC
  sensitive   = false
  type        = bool
  default     = false
}

variable "communicator" {
  description = <<DOC
    Packer currently supports three kinds of communicators:
    none - No communicator will be used. If this is set, most provisioners also can't be used.
    ssh - An SSH connection will be established to the machine. This is usually the default.
    winrm - A WinRM connection will be established.
  DOC
  sensitive   = false
  type        = string
}

variable "debug_mode" {
  description = <<DOC
    If set, sets PowerShell's PSDebug mode in order to make script debugging easier.
    For instance, setting the value to 1 results in adding this to the execute command: Set-PSDebug -Trace 1.
  DOC
  sensitive   = false
  type        = number
  default     = 0
}

variable "disable_stop_instance" {
  description = <<DOC
    Packer normally stops the build instance after all provisioners have run. For Windows instances, it is sometimes desirable to run Sysprep which will stop the instance for you.
    If this is set to true, Packer will not stop the instance but will assume that you will send the stop signal yourself through your final provisioner. You can do this with a windows-shell provisioner.
    Note that Packer will still wait for the instance to be stopped, and failing to send the stop signal yourself, when you have set this flag to true, will cause a timeout.
  DOC
  sensitive   = false
  type        = bool
  default     = false
}

variable "disk_size" {
  description = <<DOC
    The size of the hard disk for the VM in megabytes. The builder uses expandable, not fixed-size virtual hard disks,
    so the actual file representing the disk will not use the full size unless it is full. By default this is set to 40000 (about 40 GB)."
  DOC
  sensitive   = false
  type        = number
  default     = 40000
}

variable "ebs_optimized" {
  description = "Mark instance as EBS Optimized. Default false."
  sensitive   = false
  type        = bool
  default     = false
}

variable "elevated_user" {
  description = "If specified, the PowerShell script will be run with elevated privileges using the given Windows user."
  sensitive   = true
  type        = string
  default     = ""
}

variable "elevated_password" {
  description = "If specified, the PowerShell script will be run with elevated privileges using the given Windows user."
  sensitive   = true
  type        = string
  default     = ""
}

variable "encrypt_boot" {
  description = <<DOC
    Whether or not to encrypt the resulting AMI when copying a provisioned instance to an AMI.
    By default, Packer will keep the encryption setting to what it was in the source image.
    Setting false will result in an unencrypted image, and true will result in an encrypted one.
    If you have used the launch_block_device_mappings to set an encryption key and that key is the same as the one you want the image encrypted with at the end, then you don't need to set this field;
    leaving it empty will prevent an unnecessary extra copy step and save you some time.
    Please note that if you are using an account with the global "Always encrypt new EBS volumes" option set to true,
    Packer will be unable to override this setting, and the final image will be encrypted whether you set this value or not.
  DOC
  sensitive   = false
  type        = bool
  default     = true
}

variable "ena_support" {
  description = "Enable enhanced networking (ENA but not SriovNetSupport) on HVM-compatible AMIs. If set, add ec2:ModifyInstanceAttribute to your AWS IAM policy."
  sensitive   = false
  type        = bool
  default     = false
}

variable "execution_policy" {
  description = <<DOC
    To run ps scripts on windows packer defaults this to bypass and wraps the command to run. Setting this to none will prevent wrapping,
    allowing to see exit codes on docker for windows. Possible values are bypass, allsigned, default, remotesigned, restricted, undefined, unrestricted, and none.
  DOC
  sensitive   = false
  type        = string
  default     = "none"
}

variable "filters" {
  description = <<DOC
    You can select which Windows Updates are installed by defining the search criteria, a set of filters, and how many updates are installed at a time.
    Normally you would use one of the following settings:
    Name	search_criteria	filters
    Important	AutoSelectOnWebSites=1 and IsInstalled=0	$true
    Recommended	BrowseOnly=0 and IsInstalled=0	$true
    All	IsInstalled=0	$true
    Optional Only	AutoSelectOnWebSites=0 and IsInstalled=0	$_.BrowseOnly
    Recommended is the default setting.
  DOC
  sensitive   = false
  type        = list(string)
}

variable "force_deregister" {
  description = "Force Packer to first deregister an existing AMI if one with the same name already exists. Default false."
  sensitive   = false
  type        = bool
  default     = false
}

variable "force_delete_snapshot" {
  description = "Force Packer to delete snapshots associated with AMIs, which have been deregistered by force_deregister. Default false."
  sensitive   = false
  type        = bool
  default     = false
}

variable "instance_type" {
  description = "The EC2 instance type to use while building the AMI, such as t2.small."
  sensitive   = false
  type        = string
  default     = ""
}

variable "iam_instance_profile" {
  description = "The name of an IAM instance profile to launch the EC2 instance with."
  sensitive   = false
  type        = string
  default     = ""
}

variable "kms_key_id" {
  description = <<DOC
    ID, alias or ARN of the KMS key to use for AMI encryption. This only applies to the main region --
    any regions the AMI gets copied to copied will be encrypted by the default EBS KMS key for that region, unless you set region-specific keys in AMIRegionKMSKeyIDs.
    Set this value if you select encrypt_boot, but don't want to use the region's default KMS key.
    If you have a custom kms key you'd like to apply to the launch volume, and are only building in one region,
    it is more efficient to leave this and encrypt_boot empty and to instead set the key id in the launch_block_device_mappings (you can find an example below).
    This saves potentially many minutes at the end of the build by preventing Packer from having to copy and re-encrypt the image at the end of the build.
  DOC
  sensitive   = false
  type        = string
  default     = ""
}

variable "launch_block_device_mappings" {
  description = <<DOC
    Add one or more block devices before the Packer build starts.
    If you add instance store volumes or EBS volumes in addition to the root device volume,
    the created AMI will contain block device mapping information for those volumes. Amazon creates snapshots of the source instance's root volume and any other EBS volumes described here.
    When you launch an instance from this new AMI, the instance automatically launches with these additional volumes, and will restore them from snapshots taken from the source instance.
  DOC
  sensitive   = false
  type        = map(string)
  default     = {}
}

variable "max_retries" {
  description = "Max times the provisioner will retry in case of failure. Defaults to zero (0). Zero means an error will not be retried."
  sensitive   = false
  type        = number
  default     = 0
}

variable "pause_before_ssm" {
  description = <<DOC
    The time to wait before establishing the Session Manager session. The value of this should be a duration.
    Examples are 5s and 1m30s which will cause Packer to wait five seconds and one minute 30 seconds, respectively.
    If no set, defaults to 10 seconds. This option is useful when the remote port takes longer to become available.
  DOC
  sensitive   = false
  type        = string
  default     = "10s"
}

variable "pause_before" {
  description = "Sleep for duration before execution."
  sensitive   = false
  type        = string
  default     = ""
}

variable "region" {
  description = "The name of the region, such as us-east-1, in which to launch the EC2 instance to create the AMI. When chroot building, this value is guessed from environment."
  sensitive   = false
  type        = string
  default     = ""
}

variable "region_kms_key_ids" {
  description = <<DOC
    Regions to copy the ami to, along with the custom kms key id (alias or arn) to use for encryption for that region.
    Keys must match the regions provided in ami_regions. If you just want to encrypt using a default ID, you can stick with kms_key_id and ami_regions.
    If you want a region to be encrypted with that region's default key ID, you can use an empty string instead of a key id in this map.
    However, you cannot use default key IDs if you are using this in conjunction with snapshot_users -- in that situation you must use custom keys.
  DOC
  sensitive   = false
  type        = map(string)
  default     = {}
}

variable "restart_command" {
  description = "The command to execute to initiate the restart. By default this is shutdown /r /f /t 0 /c 'packer restart'."
  sensitive   = false
  type        = string
  default     = "shutdown /r /f /t 0 /c 'packer restart'"
}

variable "restart_timeout" {
  description = <<DOC
    The timeout to wait for the restart. By default this is 5 minutes. Example value: 5m.
    If you are installing updates or have a lot of startup services, you will probably need to increase this duration.
  DOC
  sensitive   = false
  type        = string
}

variable "search_criteria" {
  description = <<DOC
    You can select which Windows Updates are installed by defining the search criteria, a set of filters, and how many updates are installed at a time.
    Normally you would use one of the following settings:
    Name	search_criteria	filters
    Important	AutoSelectOnWebSites=1 and IsInstalled=0	$true
    Recommended	BrowseOnly=0 and IsInstalled=0	$true
    All	IsInstalled=0	$true
    Optional Only	AutoSelectOnWebSites=0 and IsInstalled=0	$_.BrowseOnly
    Recommended is the default setting.
  DOC
  sensitive   = false
  type        = string
  default     = "IsInstalled=0"
}

variable "secret_key" {
  description = "The secret key used to communicate with AWS. This is not required if you are using use_vault_aws_engine for authentication instead."
  sensitive   = true
  type        = string
}

variable "security_group_filter" {
  description = "Filters used to populate the security_group_ids field."
  sensitive   = false
  type        = map(string)
  default     = {}
}

variable "security_group_id" {
  description = <<DOC
    The ID (not the name) of the security group to assign to the instance.
    By default this is not set and Packer will automatically create a new temporary security group to allow SSH access.
    Note that if this is specified, you must be sure the security group allows access to the ssh_port given below.
  DOC
  sensitive   = false
  type        = string
  default     = ""
}

variable "security_group_ids" {
  description = "A list of security groups as described above. Note that if this is specified, you must omit the security_group_id."
  sensitive   = false
  type        = list(string)
  default     = []
}

variable "skip_clean" {
  description = <<DOC
    Whether to clean scripts up after executing the provisioner. Defaults to false.
    When true any script created by a non-elevated Powershell provisioner will be removed from the remote machine.
    Elevated scripts, along with the scheduled tasks, will always be removed regardless of the value set for skip_clean.
  DOC
  sensitive   = false
  type        = bool
  default     = false
}

variable "skip_credential_validation" {
  description = "Set to true if you want to skip validating AWS credentials before runtime."
  sensitive   = false
  type        = bool
  default     = false
}

variable "skip_profile_validation" {
  description = "Whether or not to check if the IAM instance profile exists. Defaults to false"
  sensitive   = false
  type        = bool
  default     = false
}

variable "skip_region_validation" {
  description = "Set to true if you want to skip validation of the ami_regions configuration option. Default false."
  sensitive   = false
  type        = bool
  default     = false
}

variable "skip_save_build_region" {
  description = <<DOC
    If true, Packer will not check whether an AMI with the ami_name exists in the region it is building in.
    It will use an intermediary AMI name, which it will not convert to an AMI in the build region.
    It will copy the intermediary AMI into any regions provided in ami_regions, then delete the intermediary AMI. Default false.
  DOC
  sensitive   = false
  type        = bool
  default     = false
}

variable "shared_credentials_file" {
  description = "Path to a credentials file to load credentials from."
  sensitive   = false
  type        = string
}

variable "shutdown_timeout" {
  description = <<DOC
    The amount of time to wait after executing the shutdown_command for the virtual machine to actually shut down.
    If the machine doesn't shut down in this time it is considered an error. By default, the time out is "5m" (five minutes).
  DOC
  sensitive   = false
  type        = string
  default     = "5m"
}

variable "snapshot_tags" {
  description = "Key/value pair tags to apply to snapshot. They will override AMI tags if already applied to snapshot."
  sensitive   = false
  type        = map(string)
  default     = {}
}

variable "snapshot_users" {
  description = <<DOC
    A list of account IDs that have access to create volumes from the snapshot(s).
    By default no additional users other than the user creating the AMI has permissions to create volumes from the backing snapshot(s).
  DOC
  sensitive   = false
  type        = list(string)
  default     = []
}

variable "snapshot_groups" {
  description = <<DOC
    A list of groups that have access to create volumes from the snapshot(s).
    By default no groups have permission to create volumes from the snapshot(s). all will make the snapshot publicly accessible.
  DOC
  sensitive   = false
  type        = list(string)
  default     = []
}

variable "source_ami" {
  description = "The source AMI whose root volume will be copied and provisioned on the currently running instance. This must be an EBS-backed AMI with a root volume snapshot that you have access to."
  sensitive   = false
  type        = string
  default     = ""
}

variable "source_ami_filter" {
  description = "Filters used to populate the source_ami field."
  sensitive   = false
  type        = map(string)
  default     = {}
}

variable "start_retry_timeout" {
  description = <<DOC
    The amount of time to attempt to start the remote process. By default this is 5m or 5 minutes.
    This setting exists in order to deal with times when SSH may restart, such as a system reboot. Set this to a higher value if reboots take a longer amount of time.
  DOC
  sensitive   = false
  type        = string
  default     = "5m"
}

variable "subnet_filter" {
  description = "Filters used to populate the subnet_id field."
  sensitive   = false
  type        = map(string)
  default     = {}
}

variable "subnet_id" {
  description = "If using VPC, the ID of the subnet, such as subnet-12345def, where Packer will launch the EC2 instance. This field is required if you are using an non-default VPC."
  sensitive   = false
  type        = string
  default     = ""
}

variable "tags" {
  description = " Key/value pair tags applied to the AMI."
  sensitive   = false
  type        = map(string)
  default     = {}
}

//variable "temporary_iam_instance_profile_policy_document" {
//  description = "Temporary IAM instance profile policy document If IamInstanceProfile is specified it will be used instead."
//  sensitive   = false
//  type        = string
//  default     = ""
//}

variable "timeout" {
  description = "If the provisioner takes more than for example 1h10m1s or 10m to finish, the provisioner will timeout and fail."
  sensitive   = false
  type        = string
  default     = "1h"
}

variable "user_data" {
  description = <<DOC
    User data to apply when launching the instance.
    Note that you need to be careful about escaping characters due to the templates being JSON.
    It is often more convenient to use user_data_file, instead.
    Packer will not automatically wait for a user script to finish before shutting down the instance this must be handled in a provisioner.
  DOC
  sensitive   = false
  type        = string
  default     = ""
}

variable "user_data_file" {
  description = "Path to a file that will be used for the user data when launching the instance."
  sensitive   = false
  type        = string
  default     = ""
}

variable "update_limit" {
  description = "If the update_limit attribute is not declared, it defaults to 1000."
  sensitive   = false
  type        = number
  default     = 1000
}

variable "valid_exit_codes" {
  description = "Valid exit codes for the script. By default this is just 0."
  sensitive   = false
  type        = list(number)
  default     = [0]
}

variable "vault_aws_engine" {
  description = <<DOC
    Get credentials from HashiCorp Vault's aws secrets engine. You must already have created a role to use.
    For more information about generating credentials via the Vault engine, see the Vault docs. If you set this flag, you must also set the below options:
    name (string) - Required. Specifies the name of the role to generate credentials against. This is part of the request URL.
    engine_name (string) - The name of the aws secrets engine. In the Vault docs, this is normally referred to as "aws", and Packer will default to "aws" if engine_name is not set.
    role_arn (string)- The ARN of the role to assume if credential_type on the Vault role is assumed_role.
      Must match one of the allowed role ARNs in the Vault role. Optional if the Vault role only allows a single AWS role ARN; required otherwise.
    ttl (string) - Specifies the TTL for the use of the STS token. This is specified as a string with a duration suffix.
      Valid only when credential_type is assumed_role or federation_token. When not specified, the default_sts_ttl set for the role will be used.
    If that is also not set, then the default value of 3600s will be used. AWS places limits on the maximum TTL allowed.
    See the AWS documentation on the DurationSeconds parameter for AssumeRole (for assumed_role credential types) and GetFederationToken (for federation_token credential types) for more details.
  DOC
  sensitive   = false
  type        = map(string)
  default     = {}
}

variable "vpc_filter" {
  description = "Filters used to populate the vpc_id field."
  sensitive   = false
  type        = map(string)
  default     = {}
}

variable "winrm_insecure" {
  description = "If true, do not check server certificate chain and host name"
  sensitive   = false
  type        = bool
  default     = false
}

variable "winrm_timeout" {
  description = "The amount of time to wait for WinRM to become available. This defaults to 30m since setting up a Windows machine generally takes a long time."
  sensitive   = false
  type        = string
}

variable "winrm_use_ntlm" {
  description = <<DOC
    If true, NTLMv2 authentication (with session security) will be used for WinRM, rather than default (basic authentication),
    removing the requirement for basic authentication to be enabled within the target guest. Further reading for remote connection authentication can be found here.
    https://docs.microsoft.com/en-us/azure/virtual-machines/windows/remote-access-winrm
  DOC
  sensitive   = false
  type        = bool
  default     = false
}

variable "winrm_use_ssl" {
  description = "If true, use HTTPS for WinRM."
  sensitive   = false
  type        = bool
  default     = false
}

variable "winrm_username" {
  description = "The username to use to connect to WinRM."
  sensitive   = false
  type        = string
}

source "amazon-ebs" "amazon-ebs" {
  access_key                  = "${var.access_key}"
  ami_name                    = "${var.ami_name}"
  ami_description             = "${var.ami_description}"
  ami_virtualization_type     = "${var.ami_virtualization_type}"
  ami_users                   = "${var.ami_users}"
  ami_groups                  = "${var.ami_groups}"
  ami_org_arns                = "${var.ami_org_arns}"
  ami_ou_arns                 = "${var.ami_ou_arns}"
  ami_product_codes           = "${var.ami_product_codes}"
  ami_regions                 = "${var.ami_regions}"
  associate_public_ip_address = "${var.associate_public_ip_address}"
  //assume_role                  = "${var.assume_role}"
  availability_zone     = "${var.availability_zone}"
  communicator          = "${var.communicator}"
  disable_stop_instance = "${var.disable_stop_instance}"
  ebs_optimized         = "${var.ebs_optimized}"
  ena_support           = "${var.ena_support}"
  encrypt_boot          = "${var.encrypt_boot}"
  force_deregister      = "${var.force_deregister}"
  force_delete_snapshot = "${var.force_delete_snapshot}"
  iam_instance_profile  = "${var.iam_instance_profile}"
  instance_type         = "${var.instance_type}"
  kms_key_id            = "${var.kms_key_id}"
  //launch_block_device_mappings = "${var.launch_block_device_mappings}"
  pause_before_ssm   = "${var.pause_before_ssm}"
  region             = "${var.region}"
  region_kms_key_ids = "${var.region_kms_key_ids}"
  secret_key         = "${var.secret_key}"
  // security_group_filter        = "${var.security_group_filter}"
  security_group_id          = "${var.security_group_id}"
  security_group_ids         = "${var.security_group_ids}"
  skip_credential_validation = "${var.skip_credential_validation}"
  skip_profile_validation    = "${var.skip_profile_validation}"
  skip_region_validation     = "${var.skip_region_validation}"
  skip_save_build_region     = "${var.skip_save_build_region}"
  shared_credentials_file    = "${var.shared_credentials_file}"
  snapshot_tags              = "${var.snapshot_tags}"
  snapshot_users             = "${var.snapshot_users}"
  snapshot_groups            = "${var.snapshot_groups}"
  source_ami                 = "${var.source_ami}"
  // source_ami_filter            = "${var.source_ami_filter}"
  // subnet_filter= "${var.subnet_filter}"
  subnet_id = "${var.subnet_id}"
  tags      = "${var.tags}"
  // temporary_iam_instance_profile_policy_document = "${var.temporary_iam_instance_profile_policy_document}"
  user_data      = "${var.user_data}"
  user_data_file = "${var.user_data_file}"
  // vault_aws_engine               = "${var.vault_aws_engine}"
  winrm_insecure = "${var.winrm_insecure}"
  winrm_timeout  = "${var.winrm_timeout}"
  winrm_use_ssl  = "${var.winrm_use_ssl}"
  winrm_username = "${var.winrm_username}"
}

build {
  sources = ["source.amazon-ebs.amazon-ebs"]

  provisioner "powershell" {
    debug_mode        = "${var.debug_mode}"
    elevated_user     = "${var.elevated_user}"
    elevated_password = "${var.elevated_password}"
    execution_policy  = "${var.execution_policy}"
    max_retries       = "${var.max_retries}"
    pause_before      = "${var.pause_before}"
    scripts = [
      "../../../../scripts/enable-rdp.ps1",
      "../../../../scripts/set-power-config.ps1",
      "../../../../scripts/compile-dotnet-assemblies.ps1"
    ]
    skip_clean          = "${var.skip_clean}"
    start_retry_timeout = "${var.start_retry_timeout}"
    timeout             = "${var.timeout}"
    valid_exit_codes    = "${var.valid_exit_codes}"
  }

  provisioner "windows-update" {
    search_criteria = "${var.search_criteria}"
    filters         = "${var.filters}"
    update_limit    = "${var.update_limit}"
  }

  provisioner "windows-restart" {
    check_registry  = "${var.check_registry}"
    max_retries     = "${var.max_retries}"
    pause_before    = "${var.pause_before}"
    restart_command = "${var.restart_command}"
    restart_timeout = "${var.restart_timeout}"
    timeout         = "${var.timeout}"
  }

  provisioner "powershell" {
    debug_mode          = "${var.debug_mode}"
    elevated_user       = "${var.elevated_user}"
    elevated_password   = "${var.elevated_password}"
    execution_policy    = "${var.execution_policy}"
    max_retries         = "${var.max_retries}"
    pause_before        = "${var.pause_before}"
    script              = "../../../../scripts/cleanup.ps1"
    skip_clean          = "${var.skip_clean}"
    start_retry_timeout = "${var.start_retry_timeout}"
    timeout             = "${var.timeout}"
    valid_exit_codes    = "${var.valid_exit_codes}"
  }


  provisioner"powershell" {
    debug_mode          = "${var.debug_mode}"
    elevated_user       = "${var.elevated_user}"
    elevated_password   = "${var.elevated_password}"
    execution_policy    = "${var.execution_policy}"
    max_retries         = "${var.max_retries}"
    pause_before        = "${var.pause_before}"
    script              = "../../../../scripts/amazon-ebs-sysprep.ps1"
    skip_clean          = "${var.skip_clean}"
    start_retry_timeout = "${var.start_retry_timeout}"
    timeout             = "${var.timeout}"
    valid_exit_codes    = "${var.valid_exit_codes}"
  }

  post-processor "manifest" {
    output     = "w2022-2108-dc-dx-en.json"
    strip_path = true
  }
}
