# pistomp-sync

Synchronisation automatique des données PiStomp entre plusieurs appareils
via rclone (bisync + copy).

## Fonctionnalités
- Synchronisation bidirectionnelle sécurisée
- Support fichiers / répertoires
- Protection multi-PiStomp
- Services systemd :
  - au boot
  - au shutdown
  - périodique (timer)

## Prérequis
- rclone configuré
- systemd

## Installation

```bash
git clone https://github.com/macfizz/pistomp-sync.git
cd pistomp-sync
sudo ./install-pistomp-sync.sh
