# Proxmox API Token Setup

Before running Terraform, create a dedicated user and API token in Proxmox with the minimum required permissions.

## 1. Create a role

In the Proxmox shell (or via SSH):

```bash
pveum role add TerraformRole -privs \
  "Datastore.Allocate \
   Datastore.AllocateSpace \
   Datastore.AllocateTemplate \
   Datastore.Audit \
   Pool.Allocate \
   Sys.Audit \
   Sys.Console \
   Sys.Modify \
   VM.Allocate \
   VM.Audit \
   VM.Clone \
   VM.Config.CDROM \
   VM.Config.Cloudinit \
   VM.Config.CPU \
   VM.Config.Disk \
   VM.Config.HWType \
   VM.Config.Memory \
   VM.Config.Network \
   VM.Config.Options \
   VM.Migrate \
   VM.PowerMgmt \
   SDN.Use"
```

## 2. Create a user

```bash
pveum user add terraform@pve --comment "Terraform service account"
```

## 3. Assign the role to the user

```bash
pveum aclmod / -user terraform@pve -role TerraformRole
```

## 4. Create an API token

```bash
pveum user token add terraform@pve terraform --privsep=0
```

`--privsep=0` means the token inherits the user's full permissions (simpler for personal production use).

Copy the token secret from the output — it's only shown once. It will look like:

```
┌──────────────┬──────────────────────────────────────┐
│ key          │ value                                │
╞══════════════╪══════════════════════════════════════╡
│ full-tokenid │ terraform@pve!terraform              │
│ value        │ xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx │
└──────────────┴──────────────────────────────────────┘
```

Your `proxmox_api_token` value is: `terraform@pve!terraform=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`

## 5. Configure terraform.tfvars

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

## 6. Run Terraform

```bash
cd terraform/
terraform init
terraform plan
terraform apply
```
