# ── Automated backups ─────────────────────────────────────────────────────────
#
# Configures daily Proxmox vzdump snapshots for all core containers (excluding
# heavy media storage volumes) to the 'local' storage pool daily at 2:00 AM.
# Keeps the last 3 daily backups.
#

