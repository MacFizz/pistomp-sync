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
- remote monté (ex: /mnt/rclone/nxt)
- systemd

## Installation

```bash
git clone https://github.com/<ton_user>/pistomp-sync.git
cd pistomp-sync
sudo ./deploy.sh
