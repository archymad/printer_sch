# HP OfficeJet Pro 9015 : diagnostic des cartouches (Windows)

Un petit outil **en lecture seule**, en français, pour aider à comprendre pourquoi des cartouches sont refusées par une HP OfficeJet Pro 9015 / série 9010.

## Fonctionnement

- Repère les imprimantes HP installées sous Windows et leur port d'impression.
- Identifie l'adresse IPv4 locale de l'imprimante, lorsqu'elle est accessible.
- Tente de lire le modèle, la version du micrologiciel et l'état via le protocole standard IPP.
- Vérifie si l'interface Web locale de l'imprimante est accessible, puis tente d'y repérer une version de firmware.
- Pose une question sur le message d'erreur des cartouches et propose des pistes adaptées.
- Enregistre un rapport `Diagnostic_HP9015.txt` **sur le Bureau de l'ordinateur**, uniquement en local.

## Installation et utilisation

1. Sur GitHub, cliquez sur **Code > Download ZIP**, puis décompressez complètement l'archive.
2. Allumez l'imprimante. Idéalement, reliez-la et le PC au même réseau Wi-Fi/Ethernet.
3. Double-cliquez sur `Lancer_Diagnostic.cmd`.
4. Si nécessaire, saisissez l'adresse IP indiquée dans le menu réseau de l'imprimante.
5. Répondez aux questions et consultez le rapport généré sur le Bureau.

Pour lire le script avant exécution, ouvrez `HP9015_Diagnostic.ps1` dans le Bloc-notes.

## Sécurité et confidentialité

- Aucun droit administrateur n'est demandé.
- Aucune installation de logiciel tiers, aucun téléchargement de firmware.
- Ne modifie ni le firmware, ni la configuration de l'imprimante, ni les cartouches.
- Les requêtes réseau visent uniquement une adresse IPv4 privée locale (IPP et interface Web de l'imprimante). Les redirections HTTP ne sont pas suivies.
- Le lanceur démarre PowerShell avec `-ExecutionPolicy Bypass` **pour ce processus uniquement**. Il ne change pas le paramètre Windows global.
- Le rapport peut inclure des noms d'imprimantes, pilotes, ports et adresses IP privées. **Relisez et masquez ces données avant de publier le rapport sur GitHub.**

## Limites

Le script ne lit pas directement la puce des cartouches. Sur certains pilotes, notamment en USB ou WSD, le firmware ne sera pas lisible automatiquement. Le statut réel des cartouches n'est pas toujours exposé via IPP.

**Il ne contourne pas HP Dynamic Security** et ne fournit aucun firmware modifié ni méthode confirmée de déblocage définitif pour la HP 9015. Une réinitialisation d'usine ne supprime pas cette fonction. L'outil sert à rassembler les informations nécessaires à un diagnostic ciblé.

Prévu pour Windows 10/11, Windows PowerShell 5.1. Non testé matériellement avec une HP OfficeJet Pro 9015.

## Fichiers

- `Lancer_Diagnostic.cmd` : lancement par double clic.
- `HP9015_Diagnostic.ps1` : script PowerShell principal.
- `.gitignore` : exclut les éventuels rapports locaux.

## Avertissement

Projet indépendant, sans affiliation à HP. Logiciel fourni tel quel, sans garantie. Aucune licence de réutilisation n'est accordée par défaut.
