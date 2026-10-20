# HP OfficeJet Pro 9015 - Diagnostic en lecture seule
# Aucune modification du firmware, des pilotes, des cartouches ou de la configuration.
# Compatible Windows PowerShell 5.1 / Windows 10 et 11.
$ErrorActionPreference = 'Stop'

function Echo([string]$s) { Write-Host $s }
function Section([string]$s) {
    Write-Host "`n  >> $s" -ForegroundColor Yellow
    Write-Host "  --------------------------------------------------" -ForegroundColor DarkGray
}
function Banner {
    Write-Host ""
    Write-Host "  +==================================================+" -ForegroundColor Cyan
    Write-Host "  |      P R I N T E R   S C A N  /  HP 9015        |" -ForegroundColor Cyan
    Write-Host "  |      Diagnostic intelligent  |  v1.1            |" -ForegroundColor Cyan
    Write-Host "  +==================================================+" -ForegroundColor Cyan
    Write-Host "   [SAFE MODE] Lecture seule - aucune modification" -ForegroundColor Green
    Write-Host ""
}
function Step([int]$percent, [string]$status) {
    Write-Progress -Id 1 -Activity "PRINTER SCAN / HP OfficeJet Pro" -Status $status -PercentComplete $percent
    Write-Host ("   [{0,3}%] {1}" -f $percent, $status) -ForegroundColor Cyan
}
function Finish-Progress {
    Write-Progress -Id 1 -Activity "PRINTER SCAN / HP OfficeJet Pro" -Completed
}

function Get-PortIP([string]$portName) {
    try {
        $p = Get-PrinterPort -Name $portName -ErrorAction Stop
        if ($p.PrinterHostAddress -and $p.PrinterHostAddress -notmatch '^WSD') { return [string]$p.PrinterHostAddress }
    } catch {}
    if ($portName -match '^IP_((?:\d{1,3}\.){3}\d{1,3})$') { return $Matches[1] }
    if ($portName -match '(?:^|://)((?:\d{1,3}\.){3}\d{1,3})(?:[:/]|$)') { return $Matches[1] }
    return $null
}
function Put-U16($writer, [int]$v) {
    $writer.Write([byte](($v -shr 8) -band 255))
    $writer.Write([byte]($v -band 255))
}
function Put-IppAttr($writer, [int]$tag, [string]$name, [string]$value) {
    $n = [System.Text.Encoding]::UTF8.GetBytes($name)
    $v = [System.Text.Encoding]::UTF8.GetBytes($value)
    $writer.Write([byte]$tag)
    Put-U16 $writer $n.Length
    $writer.Write($n)
    Put-U16 $writer $v.Length
    $writer.Write($v)
}
function Read-U16([byte[]]$b, [int]$p) { return ([int]$b[$p] * 256 + [int]$b[$p+1]) }
function Read-IppValue([int]$tag, [byte[]]$v) {
    if (($tag -eq 0x21 -or $tag -eq 0x23) -and $v.Length -eq 4) {
        return ([int64]$v[0] * 16777216 + [int64]$v[1] * 65536 + [int64]$v[2] * 256 + [int64]$v[3]).ToString()
    }
    if ($tag -eq 0x22 -and $v.Length -eq 1) { return ([bool]($v[0] -ne 0)).ToString() }
    if (($tag -ge 0x40 -and $tag -le 0x49) -or $tag -eq 0x30) {
        $s = [System.Text.Encoding]::UTF8.GetString($v)
        return ($s -replace '[\x00-\x1F]', ' ').Trim()
    }
    return "(type IPP $tag, $($v.Length) octets)"
}
function Read-Ipp([string]$ip) {
    # Requete standard IPP Get-Printer-Attributes, sans impression ni modification.
    $requested = @('printer-make-and-model', 'printer-firmware-name',
        'printer-firmware-version', 'printer-state-reasons', 'printer-alert-description',
        'printer-info', 'printer-state')
    $path = '/ipp/print'
    $ms = New-Object System.IO.MemoryStream
    $w = New-Object System.IO.BinaryWriter($ms)
    $w.Write([byte[]]@(2,0,0,11,0,0,0,1,1))
    Put-IppAttr $w 0x47 'attributes-charset' 'utf-8'
    Put-IppAttr $w 0x48 'attributes-natural-language' 'fr'
    Put-IppAttr $w 0x45 'printer-uri' "ipp://${ip}${path}"
    foreach ($a in $requested) { Put-IppAttr $w 0x44 'requested-attributes' $a }
    $w.Write([byte]3)
    $data = $ms.ToArray(); $w.Dispose(); $ms.Dispose()
    $request = [System.Net.WebRequest]::Create("http://${ip}:631${path}")
    $request.Method = 'POST'; $request.ContentType = 'application/ipp'
    $request.AllowAutoRedirect = $false
    $request.Timeout = 4000; $request.ReadWriteTimeout = 4000
    $request.ContentLength = $data.Length
    $stream = $request.GetRequestStream(); $stream.Write($data,0,$data.Length); $stream.Close()
    $response = $request.GetResponse()
    $rs = $response.GetResponseStream(); $buffer = New-Object System.IO.MemoryStream
    $rs.CopyTo($buffer); $rs.Close(); $response.Close()
    [byte[]]$b = $buffer.ToArray(); $buffer.Dispose()
    if ($b.Length -lt 9) { throw 'Reponse IPP trop courte' }
    $status = Read-U16 $b 2
    if ($status -ne 0) { throw "Code IPP : $status" }
    $results = [ordered]@{}
    $p = 8; $lastName = ''
    while ($p -lt $b.Length) {
        $tag = [int]$b[$p]; $p++
        if ($tag -eq 3) { break }
        if ($tag -le 0x0F) { $lastName = ''; continue }
        if (($p + 4) -gt $b.Length) { break }
        $nlen = Read-U16 $b $p; $p += 2
        if (($p + $nlen + 2) -gt $b.Length) { break }
        if ($nlen -gt 0) { $lastName = [System.Text.Encoding]::UTF8.GetString($b,$p,$nlen) }
        $p += $nlen
        $vlen = Read-U16 $b $p; $p += 2
        if (($p + $vlen) -gt $b.Length) { break }
        [byte[]]$val = @()
        if ($vlen -gt 0) { $val = [byte[]]$b[$p..($p+$vlen-1)] }
        $p += $vlen
        if ($lastName -and $requested -contains $lastName) {
            $vtext = Read-IppValue $tag $val
            if ($results.Contains($lastName)) { $results[$lastName] += ", $vtext" }
            else { $results[$lastName] = $vtext }
        }
    }
    return $results
}
function Read-Ews([string]$ip) {
    $r = Invoke-WebRequest -Uri "http://${ip}/" -UseBasicParsing -TimeoutSec 5 -MaximumRedirection 0 -ErrorAction Stop
    $html = [string]$r.Content
    # On ne stocke PAS la page HTML ni ses donnees personnelles.
    $text = [System.Net.WebUtility]::HtmlDecode(($html -replace '(?s)<(script|style)\b.*?</\1>', ' ' -replace '<[^>]*>', ' '))
    $firm = $null
    if ($text -match '(?i)\b(MANHTN[A-Z0-9_.-]{7,})\b') { $firm = $Matches[1] }
    elseif ($text -match '(?i)(?:firmware\s*(?:version|revision)|version\s+du\s+micrologiciel)\s*:?\s*([A-Z0-9_.-]{6,60})') { $firm = $Matches[1] }
    return @{ accessible = $true; firmware = $firm; url = "http://${ip}/" }
}

# Resume public strictement limite a des champs non personnels.
# Ne transmet jamais le rapport local, l'adresse IP ou les noms Windows.
function Make-PublicSummary([string]$fw, [string]$cat, [bool]$modelConfirmed, [bool]$ippAvailable, [bool]$ewsAvailable) {
    $validCategories = @{
        '1' = 'Puce non-HP / securite dynamique'
        '2' = 'Cartouche incompatible'
        '3' = 'Cartouche absente ou non detectee'
        '4' = 'Autre ou message inconnu'
    }
    $categoryLabel = 'Non precise'
    if ($validCategories.ContainsKey($cat)) { $categoryLabel = $validCategories[$cat] }

    $firmwareLabel = 'Non detecte automatiquement'
    $fw = [string]$fw
    $fw = $fw.Trim()
    # Valeur courte et neutre uniquement : aucun caractere libre dans l'Issue.
    if ($fw -cmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{1,59}$') { $firmwareLabel = $fw }

    $modelLabel = 'HP OfficeJet Pro 9015 : modele a confirmer'
    if ($modelConfirmed) { $modelLabel = 'HP OfficeJet Pro 9015 : identifiee' }
    $ippLabel = if ($ippAvailable) { 'Oui' } else { 'Non ou indisponible' }
    $ewsLabel = if ($ewsAvailable) { 'Oui' } else { 'Non ou indisponible' }

    return @"
## Diagnostic HP 9015 - resume anonymise

- Modele : $modelLabel
- Micrologiciel : $firmwareLabel
- Type d'erreur indique : $categoryLabel
- Reponse IPP disponible : $ippLabel
- Interface Web locale accessible : $ewsLabel

### Analyse demandee
Est-ce qu'une solution de compatibilite des cartouches est documentee pour cette version du micrologiciel ?

> Rapport genere par diag.cmd. Aucun nom de PC, nom d'imprimante Windows, numero de serie, adresse IP ou rapport complet n'est ajoute.
> Ce ticket est PUBLIC. Verifiez les informations avant de cliquer sur "Submit new issue".
"@
}
function Offer-PublicIssue([string]$fw, [string]$cat, [bool]$modelConfirmed, [bool]$ippAvailable, [bool]$ewsAvailable) {
    Write-Host ""
    Section 'Partager un resume sans informations personnelles'
    Write-Host 'Le rapport complet reste uniquement sur votre PC.' -ForegroundColor Green
    Write-Host 'Une fiche courte peut etre preparee pour GitHub.' -ForegroundColor Cyan
    Write-Host 'Attention : le ticket GitHub sera PUBLIC une fois valide.' -ForegroundColor Yellow
    $answer = (Read-Host 'Ouvrir GitHub avec le resume pre-rempli ? (O/N)').Trim()
    if ($answer -notmatch '^[OoYy]') {
        Write-Host 'Partage annule : aucune donnee envoyee.'
        return
    }
    $body = Make-PublicSummary $fw $cat $modelConfirmed $ippAvailable $ewsAvailable
    Write-Host ''
    Write-Host '--- APERCU DU RESUME ---' -ForegroundColor Cyan
    Write-Host $body
    Write-Host '--- FIN DE L APERCU ---'
    $title = 'Diagnostic cartouches HP OfficeJet Pro 9015'
    $url = 'https://github.com/archymad/printer_sch/issues/new?title=' +
        [uri]::EscapeDataString($title) + '&body=' + [uri]::EscapeDataString($body)
    try {
        Start-Process $url
        Write-Host 'Page GitHub ouverte. Verifiez puis cliquez sur Submit new issue.' -ForegroundColor Green
        Write-Host 'GitHub peut demander une connexion a votre compte sur ce PC.'
        Write-Host 'Aucune publication automatique n est faite par diag.cmd.'
    } catch {
        Write-Host 'Impossible d ouvrir GitHub automatiquement. Lien copie si possible.' -ForegroundColor Yellow
        try { Set-Clipboard -Value $url -ErrorAction Stop } catch {}
    }
}

$report = New-Object 'System.Collections.Generic.List[string]'
function Record([string]$s) { $script:report.Add($s); Echo $s }
try {
    Banner
    Step 5 'Initialisation du diagnostic...'
    Section 'Demarrage'
    Record "Date : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Record 'Mode : LECTURE SEULE, aucune action sur le firmware.'
    if (-not (Get-Command Get-Printer -ErrorAction SilentlyContinue)) {
        Record 'Cette edition de Windows ne fournit pas Get-Printer.'
        throw 'Commande Windows Get-Printer indisponible.'
    }
    Step 15 'Recherche des imprimantes installees sous Windows...'
    $all = @(Get-Printer -ErrorAction Stop)
    Step 25 'Inventaire Windows termine.'
    $hp = @($all | Where-Object { $_.Name -match 'HP|OfficeJet|Officejet' -or $_.DriverName -match 'HP.*OfficeJet' })
    Section 'Imprimantes detectees par Windows'
    if ($hp.Count -eq 0) { Record 'Aucune imprimante HP detectee dans Windows.' }
    foreach ($p in $hp) { Record "Nom : $($p.Name) | Port : $($p.PortName) | Pilote : $($p.DriverName)" }
    $candidate = @($hp | Where-Object { $_.Name -match '901[0-9]|OfficeJet Pro 90' -or $_.DriverName -match '901[0-9]' }) | Select-Object -First 1
    if (-not $candidate) { $candidate = $hp | Select-Object -First 1 }
    Step 35 'Detection de la connexion et du port reseau...'
    $ip = $null
    if ($candidate) {
        $ip = Get-PortIP $candidate.PortName
        if ($ip) { Record "Adresse reseau detectee : $ip" }
        else { Record 'Adresse reseau non trouvee (possible port WSD ou branchement USB).' }
    }
    if (-not $ip) {
        Write-Host "`nSi l'imprimante est connectee en Wi-Fi/Ethernet, relevez son adresse IP sur son ecran (Reseau)."
        $ip = (Read-Host 'Adresse IP de votre imprimante (Entree pour passer)').Trim()
    }
    Step 40 'Informations de connexion rassemblees.'
    $firmware = $null
    $ippData = $null
    $ews = $null
    if ($ip) {
        if ($ip -notmatch '^(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)$') {
            Record 'Adresse IPv4 non valide : requetes reseau annulees.'
            $ip = $null
        }
    }
    if ($ip) {
        $parts = @($ip.Split('.') | ForEach-Object { [int]$_ })
        $isLocal = ($parts[0] -eq 10 -or ($parts[0] -eq 172 -and $parts[1] -ge 16 -and $parts[1] -le 31) -or ($parts[0] -eq 192 -and $parts[1] -eq 168) -or ($parts[0] -eq 169 -and $parts[1] -eq 254))
        if (-not $isLocal) { Record 'Adresse IP non privee : pas de connexion effectuee par precaution.'; $ip = $null }
    }
    if ($ip) {
        Step 50 'Interrogation du service IPP sur le reseau local...'
        Section 'Interrogation IPP du reseau local'
        try {
            $ippData = Read-Ipp $ip
            if ($ippData.Count -eq 0) { Record 'IPP joignable, mais aucun champ diagnostique fourni.' }
            foreach ($key in $ippData.Keys) { Record "${key} : $($ippData[$key])" }
            if ($ippData.Contains('printer-firmware-version')) { $firmware = $ippData['printer-firmware-version'] }
        } catch { Record "IPP : lecture indisponible ($($_.Exception.Message))." }
        Step 65 'Interrogation IPP terminee.'
        Step 72 'Recherche du micrologiciel sur la page Web HP...'
        Section 'Interface Web integree HP (EWS)'
        try {
            $ews = Read-Ews $ip
            Record "Interface Web : joignable sur $($ews.url)"
            if ($ews.firmware) {
                Record "Version de firmware reperee sur la page d'accueil : $($ews.firmware)"
                if (-not $firmware) { $firmware = $ews.firmware }
            } else { Record 'Version non visible sur la page Web publique (consulter la rubrique Informations / Outils).' }
        } catch { Record "Interface Web : lecture automatique indisponible ($($_.Exception.Message))." }
        Step 85 'Verification du reseau local terminee.'
    } else {
        Step 85 'Aucune adresse IP locale disponible : diagnostic Windows uniquement.'
    }
    Step 90 'Identification du probleme des cartouches...'
    Section 'Probleme observe sur les cartouches'
    Echo '1 = Puce non-HP ou cartouche refusee par securite dynamique'
    Echo '2 = Cartouche incompatible'
    Echo '3 = Cartouche absente ou non detectee'
    Echo '4 = Autre / message inconnu'
    $choice = (Read-Host 'Choisissez 1, 2, 3 ou 4').Trim()
    Record "Categorie selectionnee : $choice"
    Step 95 'Preparation des recommandations...'
    Section 'Diagnostic et pistes adaptees'
    if ($firmware) { Record "Firmware recupere : $firmware" }
    else { Record 'Firmware non recupere automatiquement : consulter la page EWS et noter la version affichee.' }
    if ($candidate -and $candidate.Name -notmatch '9015' -and $candidate.DriverName -notmatch '9015') {
        Record "IMPORTANT : le modele exact 9015 n'a pas ete confirme par Windows. Verifier la reference avant toute intervention."
    }
    switch ($choice) {
        '1' {
            Record 'Blocage probable lie a la reconnaissance des puces des cartouches.'
            Record 'Aucun outil de deblocage integral fiable n a ete confirme pour la 9015.'
            Record 'Demander au vendeur un echange contre des cartouches avec puces compatibles avec la version de firmware ci-dessus, ou des cartouches reconditionnees a puce HP originale.'
            Record 'Un retour a un ancien firmware n est pas officiellement pris en charge et peut etre bloque.'
        }
        '2' { Record 'Verifier la reference de cartouche et sa region. Pour les modeles europeens HP 9015, verifier la gamme HP 963/963XL, selon la variante regionale. Demander une puce compatible avec le firmware.' }
        '3' { Record 'Verifier chaque cartouche, les protections d emballage, son insertion et les contacts propres et secs. Ne pas forcer les composants.' }
        default { Record 'Relever le message exact sur l ecran ou dans HP Smart; distinguer probleme de puce, cartouche absente ou blocage de service.' }
    }
    Record 'Desactiver les mises a jour automatiques uniquement si HP autorise ce reglage et si vous acceptez de reporter les correctifs de securite : cela ne repare pas une cartouche deja refusee.'
    Record 'Aucune mise a jour ou retrogradation n est lancee par cet outil.'
    $modelConfirmed = $false
    if ($candidate -and (($candidate.Name -match '(?i)9015') -or ($candidate.DriverName -match '(?i)9015'))) {
        $modelConfirmed = $true
    }
    if ($ippData -and $ippData.Contains('printer-make-and-model') -and $ippData['printer-make-and-model'] -match '(?i)9015') {
        $modelConfirmed = $true
    }
    $ippAvailable = ($null -ne $ippData -and $ippData.Count -gt 0)
    $ewsAvailable = ($null -ne $ews -and $ews.accessible)
    Offer-PublicIssue $firmware $choice $modelConfirmed $ippAvailable $ewsAvailable
    if ($ip -and $ews -and $ews.accessible) {
        $a = (Read-Host 'Ouvrir maintenant la page Web de l imprimante ? (O/N)').Trim()
        if ($a -match '^[OoYy]') { Start-Process "http://${ip}/" }
    }
} catch {
    Record "Erreur : $($_.Exception.Message)"
} finally {
    $dest = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Diagnostic_HP9015.txt'
    try {
        [System.IO.File]::WriteAllLines($dest, [string[]]$report.ToArray(), (New-Object System.Text.UTF8Encoding($true)))
        Step 100 'Analyse terminee : votre rapport est pret.'
        Write-Host "`n  [OK] Rapport cree : $dest" -ForegroundColor Green
    } catch {
        Write-Host "Impossible d'ecrire sur le Bureau : $($_.Exception.Message)"
    }
    Finish-Progress
    Write-Host "`n  ============== FIN DU SCAN ==============" -ForegroundColor Cyan
    Write-Host "  Vous pouvez m'envoyer le rapport (masquez votre IP si vous preferez)." -ForegroundColor Yellow
    Read-Host 'Appuyez sur Entree pour fermer' | Out-Null
}
