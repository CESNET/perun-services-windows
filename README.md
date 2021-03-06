<a href="https://perun.cesnet.cz/"><img style="float: left; position: relative;" src="https://raw.githubusercontent.com/CESNET/perun/master/perun-web-gui/src/main/webapp/img/logo.png"></a>
## Perun services for Windows ##

This repository contains scripts, which are used by [Perun](https://perun.cesnet.cz/web/) for provisioning and de-provisioning users to your services running Windows (managing access rights to them). Perun can manage any service, which has either accessible API or has accessible config files. We will be happy to help you with writing your own scripts for managing your service.

### Related projects ###

* [Perun](https://github.com/CESNET/perun) - main Perun repository
* [Perun WUI](https://github.com/zlamalp/perun-wui) - next-gen web user interface for Perun
* [Google Group connector](https://github.com/CESNET/google-group-connector) - allow provisioning of Google groups on your domain

### Sources structure ###

* **libs/** - various modules used in the connector, for example, 7zip4Powershell to process tar files.
* **conf/** - configuration files, here you can define white/blacklists of services, temp files location, logs location, etc.
* **services/** - These Powershell scripts process newly received files on the destination machine and perform change itself.
* **perun_connector.ps1** - Main Powershell script, handling all errors and calls service process scripts.

## Requirements 
- at least version Windows Server 2019 or Windows 10 1809   
Windows Connector for Perun uses native OpenSSH support on Windows OS [since Windows Server 2019, Windows 10 1809](https://docs.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse).

## Installation
1. Initial setup of OpenSSH   
[Please follow official installation documentation from Microsoft](https://docs.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse)
2. Set up the PowerShell as the default shell for SSH:   
```powershell
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force
```
3. Create an account for Perun (<PERUN_USER>) on the target machine (or create as a domain account). It's recommended to load user profile using the following command:
```
Start-Process cmd /c -Credential $credentials -ErrorAction SilentlyContinue -LoadUserProfile
```
4. Allow SSH only for the specific account by adding the following line to the end of the `%programdata%\ssh\sshd_config` file. [Official documentation on allowing or denying accounts](https://docs.microsoft.com/en-us/windows-server/administration/openssh/openssh_server_configuration#allowgroups-allowusers-denygroups-denyusers)
```
# For local account
AllowUsers username
``` 
5. Forbid `password authentication` by changing `sshd_config`.
```
# From
#PasswordAuthentication yes
# To
PasswordAuthentication no
```
6. Copy the public key for Perun to following files:
  - `C:\Users\<PERUN_USER>\.ssh\authorized_keys` (note that only perun user have rights for `.ssh` folder and files see the [official documentation of deploying the keys](https://docs.microsoft.com/en-us/windows-server/administration/openssh/openssh_keymanagement#deploying-the-public-key))
  - `C:\ProgramData\ssh\administrators_authorized_keys`     
  
Both files should look like:
```
command="& c:\<INSTALLATION_FOLDER>\perun\perun_connector.ps1 $input; exit $LASTEXITCODE" ssh-rsa publickey perun@idm.ics.muni.cz
```

7. Restart sshd service
```
Restart-Service sshd
```
8. Test Connection
