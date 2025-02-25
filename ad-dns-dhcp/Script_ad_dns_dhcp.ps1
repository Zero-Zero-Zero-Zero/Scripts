# On commence par la déclaration des fonctions et variables, vérification IP, etc.

# Fonction pour le template des vérifications des adresses IP (format, séparation, etc.)
function Test-IPAddress {
    param ([string]$ip)  # On travaille ici avec une chaîne de caractères, l'adresse IP entrée par l'utilisateur
    $regex = '^\d{1,3}(\.\d{1,3}){3}$'  # on appelle la variable regex par convention car c'est une séquence de caractères qui définit un motif spécial.
    if ($ip -match $regex) {  # Si l'ip -match la variable regex qui définit le motif spécial ip, alors on peut passer à la suite
        $bytes = $ip.Split('.')  # Divise l'adresse IP en segments, par octets, et le stocke dans bytes
        for ($i = 0; $i -lt 4; $i++) {  # Vérifie chaque segment pour s'assurer qu'il est bien entre 0 et 255 en itérant avec la variable i
            if ([int]$bytes[$i] -gt 255) {  # On précise que l'on manipule des intégrales et on applique le test créé dans la variable $i pour vérifier que chaque octet est inférieur ou égal à 255, sinon return false 
                return $false
            }
        }
        return $true
    }
    return $false
}

# Fonction pour vérifier si deux adresses IP sont sur le même réseau
function Test-SameNetwork {
    param (
        [string]$ip1,  # Les deux sont des paramètres positionnels : 1er argument devient $ip1, 2e devient $ip2; 
        [string]$ip2
    )
    try {
        $ip1Obj = [System.Net.IPAddress]::Parse($ip1)  # Conversion de l'IP en objet pour manipulations plus précises grâce au parsing
        $ip2Obj = [System.Net.IPAddress]::Parse($ip2)
        $mask = [IPAddress]::Parse("255.255.255.0")  # Utilisation d'un masque de sous-réseau par défaut en /24 (255.255.255.0)

        $network1 = [System.Net.IPAddress]::Parse($ip1Obj.Address -band $mask.Address)  # Calcul des adresses réseau pour comparer si elles sont identiques
        $network2 = [System.Net.IPAddress]::Parse($ip2Obj.Address -band $mask.Address)

        return ($network1.Equals($network2))  # Si les deux adresses réseau sont les mêmes, elles sont dans le même sous-réseau
    }
    catch {
        Write-Host "Erreur lors de la vérification du réseau: $_"
        return $false
    }
}

# Fonction pour demander les informations à l'utilisateur
function Get-UserInput {
    do {
        # Utilisation de la variable de script directement sans déclaration préalable
        $script:domain = Read-Host "Entrez le nom de domaine (ex: example.local)"
    } while ([string]::IsNullOrEmpty($script:domain))

    # Afficher les informations actuelles de configuration IP
    Write-Host "Configuration actuelle :"
    ipconfig

    do {
        # Utilisation de la variable de script directement sans déclaration préalable
        $script:ip = Read-Host "Entrez l'adresse IP du serveur (fixez une adresse IP statique)"
        if (-not (Test-IPAddress $script:ip)) {
            Write-Host "Adresse IP invalide. Veuillez entrer une adresse IP valide (format: xxx.xxx.xxx.xxx)."
        }
    } while (-not (Test-IPAddress $script:ip))

    do {
        # Utilisation de la variable de script directement sans déclaration préalable
        $script:gateway = Read-Host "Entrez l'adresse IP de la passerelle"
        if (-not (Test-IPAddress $script:gateway)) {
            Write-Host "Adresse IP invalide. Veuillez entrer une adresse IP valide (format: xxx.xxx.xxx.xxx)."
        }
    } while (-not (Test-IPAddress $script:gateway))

    do {
        # Utilisation de la variable de script directement sans déclaration préalable
        $script:dns = Read-Host "Entrez l'adresse IP du serveur DNS"
        if (-not (Test-IPAddress $script:dns)) {
            Write-Host "Adresse IP invalide. Veuillez entrer une adresse IP valide (format: xxx.xxx.xxx.xxx)."
        }
    } while (-not (Test-IPAddress $script:dns))

    # Plages DHCP 
    do {
        # Utilisation de la variable de script directement sans déclaration préalable
        $script:dhcpStartRange = Read-Host "Entrez la plage de début DHCP"
        if (-not (Test-IPAddress $script:dhcpStartRange)) {
            Write-Host "Adresse IP invalide. Veuillez entrer une adresse IP valide (format: xxx.xxx.xxx.xxx)."
        }
    } while (-not (Test-IPAddress $script:dhcpStartRange))

    do {
        # Utilisation de la variable de script directement sans déclaration préalable
        $script:dhcpEndRange = Read-Host "Entrez la plage de fin DHCP"
        if (-not (Test-IPAddress $script:dhcpEndRange)) {
            Write-Host "Adresse IP invalide. Veuillez entrer une adresse IP valide (format: xxx.xxx.xxx.xxx)."
        }
    } while (-not (Test-IPAddress $script:dhcpEndRange))

    if (-not (Test-SameNetwork $script:dhcpStartRange $script:dhcpEndRange)) {
        Write-Host "Les plages d'adresses DHCP ne sont pas sur le même réseau. Veuillez entrer des adresses IP valides."
        Get-UserInput
        return
    }

    # Vérification que l'adresse IP et la passerelle sont sur le même réseau
    if (-not (Test-SameNetwork $script:ip $script:gateway)) {
        Write-Host "L'adresse IP du serveur et la passerelle ne sont pas sur le même réseau. Veuillez entrer des adresses IP valides."
        Get-UserInput
        return
    }
}

# Demande des informations à l'utilisateur
Get-UserInput

# Désactiver DHCP sur l'interface réseau active avant de configurer une adresse IP statique
$interfaceName = (Get-NetAdapter | Where-Object {$_.Status -eq "Up"}).Name

if ($interfaceName) {
   try {
       # Désactiver DHCP si activé
       Set-NetIPInterface -InterfaceAlias "$interfaceName" -Dhcp Disabled
        
       # Configuration de l'adresse IP statique avec un masque /24 par défaut en utilisant la variable script:
       New-NetIPAddress -IPAddress "$script:ip" -InterfaceAlias "$interfaceName" -DefaultGateway "$script:gateway" -PrefixLength 24

       # Configuration du serveur DNS en utilisant la variable script:
       Set-DnsClientServerAddress -InterfaceAlias "$interfaceName" -ServerAddresses @($script:dns)

   } catch {
       Write-Host "Erreur lors de la configuration de l'adresse IP ou du DNS : $_"

       # Pause délibérée pour permettre à l'utilisateur d'intervenir si nécessaire
       Start-Sleep -Seconds 10 
       exit 
   }
} else {
   Write-Host "Aucune interface réseau active n'a été trouvée."
   exit 
}

# Installation des rôles AD, DNS, et DHCP
Install-WindowsFeature AD-Domain-Services, DNS, DHCP -IncludeManagementTools

# Pause de 10 secondes pour permettre à la configuration IP de prendre effet
Write-Host "Configuration IP en cours. Veuillez patienter..."
Start-Sleep -Seconds 10

# Promotion du serveur en contrôleur de domaine avec un mot de passe sécurisé prédéfini
$securePassword = ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force

Install-ADDSForest ` # installation et promotion de l'AD avec les variables entrées et les bons arguments 
   -DomainName "$script:domain" `
   -DomainNetbiosName ($script:domain.Split('.')[0]) `
   -ForestMode "WinThreshold" `
   -DomainMode "WinThreshold" `
   -InstallDns `
   -SafeModeAdministratorPassword $securePassword `
   -Force `
   -NoRebootOnCompletion

# Configuration du DHCP uniquement après avoir configuré l'IP statique.
try {
   # Ajouter la portée DHCP avec les paramètres fournis par l'utilisateur.
   Add-DhcpServerv4Scope `
       -Name "Scope1" `
       -StartRange "$script:dhcpStartRange" `
       -EndRange "$script:dhcpEndRange" `
       -SubnetMask "255.255.255.0" `
       -ErrorAction Stop
   
   # Correctement construire le ScopeId comme une seule chaîne représentant l'adresse réseau.
   # En supposant que la plage de début soit quelque chose comme 192.168.1.x, nous n'utilisons que les trois premiers octets.
   $scopeId = ($script:dhcpStartRange.Split('.')[0..2] + '0') -join '.'

   Set-DhcpServerv4Scope `
       -ScopeId $scopeId `
       -State Active

   Write-Host "Le DHCP a été configuré avec succès."
} catch {
   Write-Host "Erreur lors de la configuration du DHCP : $_"
}

Write-Host "Configuration terminée."
