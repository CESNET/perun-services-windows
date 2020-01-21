# Perun Windows Connector
## Requirements 
- at least version Windows Server 2019 or Windows 10 1809   
Windows Connector for Perun uses native OpenSSH support on Windows OS [since Windows Server 2019, Windows 10 1809](https://docs.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse).

## Instalation
1. Initial setup of OpenSSH   
[Please follow official instalation documentation from Microsoft](https://docs.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse)
2. Set up the PowerShell as the default shell for SSH:   
```powershell
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force
```
3. Create an account for Perun (<PERUN_USER>) on the target machine (or create as a domain account). It's recomended to load user profile using following command:
```
Start-Process cmd /c -Credential $credentials -ErrorAction SilentlyContinue -LoadUserProfile
```
4. Allow SSH only for the specific account by adding the following line to end of the `%programdata%\ssh\sshd_config` file. [Official documentation on allowing or denying accounts](https://docs.microsoft.com/en-us/windows-server/administration/openssh/openssh_server_configuration#allowgroups-allowusers-denygroups-denyusers)
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