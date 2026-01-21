
$env:PACKER_LOG=1
$env:PACKER_LOG_PATH='./output/packer-build-vmware-iso-w2k16-1607-dc-core-en.log'

packer build -var-file '../vmware-iso/windows/w2k16-1607/w2k16-1607-dc-core-en/vmware-iso-w2k16-1607-dc-core-en.pkvars.hcl' '../vmware-iso/windows/w2k16-1607/w2k16-1607-dc-core-en/vmware-iso-w2k16-1607-dc-core-en.pkr.hcl'
