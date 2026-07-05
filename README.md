# vm-bootstrap

A small collection of shell scripts for preparing **Debian** and **Ubuntu** virtual machine templates on **Synology Virtual Machine Manager**.

The project was created to automate my own workflow. It is **not** intended to be a universal Linux provisioning framework.

## Purpose

When creating temporary virtual machines for experiments, development or testing, I found myself repeating exactly the same steps every time:

- update the system
- install the same packages
- configure locales and timezone
- enable IP forwarding
- install qemu-guest-agent
- install gost
- configure passwordless sudo
- install SSH public keys
- suppress the login banner
- prepare the VM for cloning

This repository automates those repetitive tasks.

## Supported Operating Systems

Currently only the following distributions are supported:

- Debian
- Ubuntu

The scripts explicitly check the operating system and will refuse to run on anything else.

Support for additional distributions may be added in the future if I personally need them.

## Tested Versions

The scripts have been tested only on:

- Debian 13
- Ubuntu 24.04 LTS

They may work on other versions of Debian or Ubuntu, but this has not been verified.

## Important

These scripts **do not install an operating system**.

The initial installation of Debian or Ubuntu must be performed manually using the normal installer.

Once the operating system has been installed and you have logged in for the first time, the scripts in this repository can be used to configure the VM.

## Installation

### Debian

```bash
su -c "wget -qO- https://raw.githubusercontent.com/szonov/vm-bootstrap/main/setup.sh | bash"
```

### Ubuntu

```bash
wget -qO- https://raw.githubusercontent.com/szonov/vm-bootstrap/main/setup.sh | sudo bash
```

The setup script will:

- update the system
- install commonly used packages
- install qemu-guest-agent
- install gost
- configure locales
- configure timezone
- enable IPv4 forwarding
- configure passwordless sudo
- install the configured SSH public key
- create `.hushlogin`
- install the helper commands below

## Available Commands

### rename-host

Changes the hostname of the VM and updates `/etc/hosts`.

Example:

```bash
rename-host my-vm
```

### prepare-template

Prepares the virtual machine for cloning by:

- updating the system
- removing unused packages
- cleaning the APT cache
- removing SSH host keys
- cleaning machine-id
- cleaning cloud-init state (if installed)
- removing DHCP leases
- cleaning logs
- cleaning temporary files
- removing user history files

It also installs a systemd service that automatically regenerates SSH host keys during the first boot of every clone.

After running the command:

```bash
prepare-template
```

shut down the VM:

```bash
sudo poweroff
```

The VM is now ready to be used as a template or cloned.

## Personal Defaults

This project contains several settings that reflect my own working environment, including:

- `Asia/Novosibirsk` timezone
- `ru_RU.UTF-8` locale
- installation of `gost`
- my own SSH public key

These defaults are intentional.

The project is designed to be easy to fork and customize. If your environment differs, simply modify `setup.sh` to match your own preferences.

## Synology Virtual Machine Manager

The scripts are developed and tested exclusively on virtual machines running under **Synology Virtual Machine Manager**.

Compatibility with other hypervisors (such as KVM, Proxmox VE, VMware ESXi, Hyper-V, VirtualBox, etc.) has not been tested and is not guaranteed.

## License

This project is licensed under the MIT License.

Although it was originally created for my own workflow, you are welcome to use, modify and redistribute it under the terms of the MIT License.

See the [LICENSE](LICENSE) file for details.
