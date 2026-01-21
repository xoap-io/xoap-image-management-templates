packer {
  required_plugins {
    windows-update = {
      version = "0.14.0"
      source  = "github.com/rgl/windows-update"
    }
  }
}

variable "boot_command" {
  description = <<DOC
    The boot_command is an array of strings. The strings are all typed in sequence.
    It is an array only to improve readability within the template.
  DOC
  sensitive   = false
  type        = list(string)
}

variable "boot_wait" {
  description = <<DOC
    The time to wait after booting the initial virtual machine before typing the boot_command. The value of this should be a duration.
    Examples are 5s and 1m30s which will cause Packer to wait five seconds and one minute 30 seconds, respectively.
    If this isn't specified, the default is 10s or 10 seconds. To set boot_wait to 0s, use a negative number, such as -1s.
  DOC
  sensitive   = false
  type        = string
  default     = "10s"
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

variable "compression_level" {
  description = "An integer representing the compression level to use when creating the Vagrant box. Valid values range from 0 to 9, with 0 being no compression and 9 being the best compression. By default, compression is enabled at level 6."
  sensitive   = false
  type        = number
  default     = 6
}

variable "cpus" {
  description = "Number of CPUs."
  sensitive   = false
  type        = number
  default     = 2
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

variable "disk_adapter_type" {
  description = <<DOC
    The adapter type of the VMware virtual disk to create. This option is for advanced usage, modify only if you know what you're doing.
    Some of the options you can specify are ide, sata, nvme or scsi (which uses the "lsilogic" scsi interface by default).
    If you specify another option, Packer will assume that you're specifying a scsi interface of that specified type.
    For more information, please consult Virtual Disk Manager User's Guide for desktop VMware clients. For ESXi, refer to the proper ESXi documentation.
  DOC
  sensitive   = false
  type        = string
  default     = "scsi"
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

variable "disk_type_id" {
  description = <<DOC
    The disk type ID to use for the VM. If this isn't specified, the default is \"37\" (for Standard Fixed-VHD).
    See https://docs.microsoft.com/en-us/rest/api/compute/disktypes/list for a list of disk type IDs.
  DOC
  sensitive   = false
  type        = string
  default     = "1"
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

variable "execution_policy" {
  description = <<DOC
    To run ps scripts on windows packer defaults this to "bypass" and wraps the command to run. Setting this to "none" will prevent wrapping,
    allowing to see exit codes on docker for windows. Possible values are bypass, allsigned, default, remotesigned, restricted, undefined, unrestricted, and none.
  DOC
  sensitive   = false
  type        = string
  default     = "none"
}

variable "floppy_files" {
  description = <<DOC
    A list of files to place onto a floppy disk that is attached when the VM is booted.
    Currently, no support exists for creating sub-directories on the floppy. Wildcard characters (\*, ?, and []) are allowed.
    Directory names are also allowed, which will add all the files found in the directory to the floppy.
  DOC
  sensitive   = false
  type        = list(string)
  default     = []
}

variable "floppy_dirs" {
  description = <<DOC
    A list of directories to place onto the floppy disk recursively. This is similar to the floppy_files option except that the directory structure is preserved.
    This is useful for when your floppy disk includes drivers or if you just want to organize it's contents as a hierarchy.
    Wildcard characters (\*, ?, and []) are allowed. The maximum summary size of all files in the listed directories are the same as in floppy_files.
  DOC
  sensitive   = false
  type        = list(string)
  default     = []
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

variable "format" {
  description = <<DOC
    Either "ovf", "ova" or "vmx", this specifies the output format of the exported virtual machine.
    This defaults to "ovf" for remote (esx) builds, and "vmx" for local builds. Before using this option, you need to install ovftool.
    Since ovftool is only capable of password based authentication remote_password must be set when exporting the VM from a remote instance.
    If you are building locally, Packer will create a vmx and then export that vm to an ovf or ova.
    Packer will not delete the vmx and vmdk files; this is left up to the user if you don't want to keep those files.
  DOC
  sensitive   = false
  type        = string
  default     = "vmx"
}

variable "guest_os_type" {
  description = <<DOC
    The guest OS type being installed. This will be set in the VMware VMX.
    By default this is other. By specifying a more specific OS type, VMware may perform some optimizations or virtual hardware changes to better support
    the operating system running in the virtual machine. Valid values differ by platform and version numbers,
    and may not match other VMware API's representation of the guest OS names. Consult your platform for valid values.
  DOC
  sensitive   = false
  type        = string
  default     = "other"
}

variable "headless" {
  description = <<DOC
    Packer defaults to building VMware virtual machines by launching a GUI that shows the console of the machine being built.
    When this value is set to true, the machine will start without a console. For VMware machines,
    Packer will output VNC connection information in case you need to connect to the console to debug the build process.
    Some users have experienced issues where Packer cannot properly connect to a VM if it is headless;
    this appears to be a result of not ever having launched the VMWare GUI and accepting the evaluation license, or supplying a real license.
    If you experience this, launching VMWare and accepting the license should resolve your problem.
  DOC
  sensitive   = false
  type        = string

}

variable "iso_checksum" {
  description = <<DOC
    The checksum for the ISO file or virtual hard drive file. The type of the checksum is specified within the checksum field as a prefix, ex: "md5:{$checksum}".
    The type of the checksum can also be omitted and Packer will try to infer it based on string length.
    Valid values are "none", "{$checksum}", "md5:{$checksum}", "sha1:{$checksum}", "sha256:{$checksum}", "sha512:{$checksum}" or "file:{$path}".
    Here is a list of valid checksum values:
      md5:090992ba9fd140077b0661cb75f7ce13
      090992ba9fd140077b0661cb75f7ce13
      sha1:ebfb681885ddf1234c18094a45bbeafd91467911
      ebfb681885ddf1234c18094a45bbeafd91467911
      sha256:ed363350696a726b7932db864dda019bd2017365c9e299627830f06954643f93
      ed363350696a726b7932db864dda019bd2017365c9e299627830f06954643f93
      file:http://releases.ubuntu.com/20.04/SHA256SUMS
      file:file://./local/path/file.sum
      file:./local/path/file.sum
      none
      Although the checksum will not be verified when it is set to "none", this is not recommended since these files can be very
    large and corruption does happen from time to time.
  DOC
  sensitive   = false
  type        = string
}

variable "iso_url" {
  description = "A URL to the ISO containing the installation image or virtual hard drive (VHD or VHDX) file to clone."
  sensitive   = false
  type        = string
}

variable "keep_input_artifact" {
  description = <<DOC
    If set to true, the input artifact will be kept in the output directory.When true, preserve the artifact we use to create the vagrant box.
    Defaults to false, except when you set a cloud provider (e.g. aws, azure, google, digitalocean).
    In these cases deleting the input artifact would render the vagrant box useless, so we always keep these artifacts -- even if you specifically set "keep_input_artifact":false
  DOC
  sensitive   = false
  type        = bool
  default     = false
}

variable "max_retries" {
  description = "Max times the provisioner will retry in case of failure. Defaults to zero (0). Zero means an error will not be retried."
  sensitive   = false
  type        = number
  default     = 0
}

variable "memory" {
  description = "The amount, in megabytes, of RAM to assign to the VM. By default, this is 1 GB."
  sensitive   = false
  type        = number
}

variable "network_adapter_type" {
  description = <<DOC
    The network adapter type to use for the VM.This is the ethernet adapter type the the virtual machine will be created with.
    By default the e1000 network adapter type will be used by Packer.
    For more information, please consult Choosing a network adapter for your virtual machine for desktop VMware clients.
    For ESXi, refer to the proper ESXi documentation.
  DOC
  sensitive   = false
  type        = string
  default     = "e1000"
}

variable "output_directory" {
  description = "This setting specifies the directory that artifacts from the build, such as the virtual machine files and disks, will be output to."
  sensitive   = false
  type        = string
}

variable "ovftool_options" {
  description = <<DOC
    Extra options to pass to ovftool during export. Each item in the array is a new argument.
    The options --noSSLVerify, --skipManifestCheck, and --targetType are used by Packer for remote exports,
    and should not be passed to this argument. For ovf/ova exports from local builds, Packer does not automatically set any ovftool options.
  DOC
  sensitive   = false
  type        = list(string)
  default     = []
}

variable "pause_before" {
  description = "Sleep for duration before execution."
  sensitive   = false
  type        = string
  default     = ""
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

variable "skip_compaction" {
  description = <<DOC
    VMware-created disks are defragmented and compacted at the end of the build process using vmware-vdiskmanager or vmkfstools in ESXi.
    In certain rare cases, this might actually end up making the resulting disks slightly larger. If you find this to be the case,
    you can disable compaction using this configuration value. Defaults to false.
    Default to true for ESXi when disk_type_id is not explicitly defined and false otherwise.
  DOC
  sensitive   = false
  type        = bool
  default     = false
}

variable "shutdown_command" {
  description = <<DOC
    The command to use to gracefully shut down the machine once all provisioning is complete.
    By default this is an empty string, which tells Packer to just forcefully shut down the machine.
    This setting can be safely omitted if for example, a shutdown command to gracefully halt the machine is configured inside a provisioning script.
    If one or more scripts require a reboot it is suggested to leave this blank (since reboots may fail) and instead specify the final shutdown command in your last script.
  DOC
  sensitive   = false
  type        = string
  default     = ""
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

variable "start_retry_timeout" {
  description = <<DOC
    The amount of time to attempt to start the remote process. By default this is 5m or 5 minutes.
    This setting exists in order to deal with times when SSH may restart, such as a system reboot. Set this to a higher value if reboots take a longer amount of time.
  DOC
  sensitive   = false
  type        = string
  default     = "5m"
}

variable "timeout" {
  description = "If the provisioner takes more than for example 1h10m1s or 10m to finish, the provisioner will timeout and fail."
  sensitive   = false
  type        = string
  default     = "1h"
}

variable "tools_upload_flavor" {
  description = "The flavor of the VMware Tools ISO to upload into the VM. Valid values are darwin, linux, and windows. By default, this is empty, which means VMware tools won't be uploaded."
  sensitive   = false
  type        = string
  default     = ""
}

variable "tools_upload_path" {
  description = <<DOC
    The path in the VM to upload the VMware tools. This only takes effect if tools_upload_flavor is non-empty.
    This is a configuration template that has a single valid variable: Flavor, which will be the value of tools_upload_flavor.
    By default the upload path is set to {{.Flavor}}.iso. This setting is not used when remote_type is esx5.
  DOC
  sensitive   = false
  type        = string
  default     = "{{.Flavor}}.iso"
}

variable "tools_source_path" {
  description = <<DOC
    The path on your local machine to fetch the vmware tools from.
    If this is not set but the tools_upload_flavor is set, then Packer will try to load the VMWare tools from the VMWare installation directory.
  DOC
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

variable "vagrant_output_directory" {
  description = <<DOC
    The full path to the box file that will be created by this post-processor. This is a template engine.
    Therefore, you may use user variables and template functions in this field. The following extra variables are also available in this engine:
    Provider: The Vagrant provider the box is for
    ArtifactId: The ID of the input artifact.
    BuildName: The name of the build.
    By default, the value of this config is packer_{{.BuildName}}_{{.Provider}}.box.
  DOC
  sensitive   = false
  type        = string
  default     = "packer_{{.BuildName}}_{{.Provider}}.box"
}

variable "vagrant_version" {
  description = "The version you want to give the Vagrant Box output."
  sensitive   = false
  type        = string
  default     = "v0.0.1"
}

variable "version" {
  description = <<DOC
    The vmx hardware version for the new virtual machine (https://kb.vmware.com/s/article/1003746).
    Only the default value has been tested, any other value is experimental. Default value is 9."
  DOC
  sensitive   = false
  type        = string
  default     = "9"
}

variable "vm_name" {
  description = "This is the name of the new virtual machine, without the file extension. By default this is packer-BUILDNAME, where BUILDNAME is the name of the build."
  sensitive   = false
  type        = string
}

variable "vmx_remove_ethernet_interfaces" {
  description = <<DOC
    Remove all ethernet interfaces from the VMX file after building. This is for advanced users who understand the ramifications,
    but is useful for building Vagrant boxes since Vagrant will create ethernet interfaces when provisioning a box. Defaults to false.
  DOC
  sensitive   = false
  type        = bool
  default     = false
}

variable "vnc_port_min" {
  description = <<DOC
    The minimum and maximum port to use for VNC access to the virtual machine. The builder uses VNC to type the initial boot_command. Because Packer generally runs in parallel, Packer uses a randomly chosen port in this range that appears available. By default this is 5900 to 6000. The minimum and maximum ports are inclusive.
  DOC
  sensitive   = false
  type        = number
  default     = 5900
}

variable "vnc_port_max" {
  description = "VNC Port Max"
  sensitive   = false
  type        = number
  default     = 6000
}

variable "winrm_insecure" {
  description = "If true, do not check server certificate chain and host name"
  sensitive   = false
  type        = bool
  default     = false
}

variable "winrm_password" {
  description = "The password to use to connect to WinRM."
  sensitive   = false
  type        = string
}

variable "winrm_port" {
  description = "The WinRM port to connect to. This defaults to 5985 for plain unencrypted connection and 5986 for SSL when winrm_use_ssl is set to true."
  sensitive   = false
  type        = string
  default     = "5985"
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

source "vmware-iso" "vmware-iso" {
  boot_command                   = "${var.boot_command}"
  boot_wait                      = "${var.boot_wait}"
  communicator                   = "${var.communicator}"
  cpus                           = "${var.cpus}"
 disk_adapter_type              = "${var.disk_adapter_type}"
  disk_size                      = "${var.disk_size}"
  disk_type_id                   = "${var.disk_type_id}"
  floppy_files                   = "${var.floppy_files}"
  floppy_dirs                    = "${var.floppy_dirs}"
  format                         = "${var.format}"
  guest_os_type                  = "${var.guest_os_type}"
  headless                       = "${var.headless}"
  iso_checksum                   = "${var.iso_checksum}"
  iso_url                        = "${var.iso_url}"
  memory                         = "${var.memory}"
  network_adapter_type           = "${var.network_adapter_type}"
  output_directory               = "${var.output_directory}"
  ovftool_options                = "${var.ovftool_options}"
  skip_compaction                = "${var.skip_compaction}"
  shutdown_command               = "${var.shutdown_command}"
  shutdown_timeout               = "${var.shutdown_timeout}"
  tools_upload_flavor            = "${var.tools_upload_flavor}"
  tools_upload_path              = "${var.tools_upload_path}"
  tools_source_path              = "${var.tools_source_path}"
  version                        = "${var.version}"
  vm_name                        = "${var.vm_name}"
  vmx_remove_ethernet_interfaces = "${var.vmx_remove_ethernet_interfaces}"
  vnc_port_min                   = "${var.vnc_port_min}"
  vnc_port_max                   = "${var.vnc_port_max}"
  winrm_insecure                 = "${var.winrm_insecure}"
  winrm_password                 = "${var.winrm_password}"
  winrm_port                     = "${var.winrm_port}"
  winrm_timeout                  = "${var.winrm_timeout}"
  winrm_use_ntlm                 = "${var.winrm_use_ntlm}"
  winrm_use_ssl                  = "${var.winrm_use_ssl}"
  winrm_username                 = "${var.winrm_username}"
}

build {
  sources = ["source.vmware-iso.vmware-iso"]

  provisioner "powershell" {
    debug_mode        = "${var.debug_mode}"
    elevated_user     = "${var.elevated_user}"
    elevated_password = "${var.elevated_password}"
    execution_policy  = "${var.execution_policy}"
    max_retries       = "${var.max_retries}"
    pause_before      = "${var.pause_before}"
    scripts = [
      "../../scripts/configure-winrm.ps1",
      "../../scripts/enable-rdp.ps1",
      "../../scripts/set-power-config.ps1",
      "../../scripts/compile-dotnet-assemblies.ps1"
    ]
    skip_clean          = "${var.skip_clean}"
    start_retry_timeout = "${var.start_retry_timeout}"
    timeout             = "${var.timeout}"
    valid_exit_codes    = "${var.valid_exit_codes}"
  }

  provisioner "windows-restart" {
    check_registry  = "${var.check_registry}"
    max_retries     = "${var.max_retries}"
    pause_before    = "${var.pause_before}"
    restart_command = "${var.restart_command}"
    restart_timeout = "${var.restart_timeout}"
    timeout         = "${var.timeout}"
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
    script              = "../../scripts/cleanup.ps1"
    skip_clean          = "${var.skip_clean}"
    start_retry_timeout = "${var.start_retry_timeout}"
    timeout             = "${var.timeout}"
    valid_exit_codes    = "${var.valid_exit_codes}"
  }

  post-processor "vagrant" {
    keep_input_artifact  = "${var.keep_input_artifact}"
    compression_level    = "${var.compression_level}"
    output               = "${var.vagrant_output_directory}/${var.vm_name}-${var.vagrant_version}.box"
    vagrantfile_template = "${path.root}/vagrant-${var.vm_name}.template"
  }

  post-processor "checksum" {
    checksum_types = ["sha1"]
    output         = "./output/packer_{{.BuildName}}_{{.ChecksumType}}.checksum"
  }

  post-processor "manifest" {
    output     = "./output/${var.vm_name}.json"
    strip_path = true
  }
}
