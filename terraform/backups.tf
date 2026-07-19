# ── Automated backups ─────────────────────────────────────────────────────────
#
# Configures daily Proxmox vzdump snapshots for all core containers (excluding
# heavy media storage volumes) to the 'local' storage pool daily at 2:00 AM.
# Keeps the last 3 daily backups.
#

resource "null_resource" "backup_schedule" {
  triggers = {
    cron_line = "00 02 * * *           root vzdump 201 206 300 301 302 303 304 305 306 307 310 311 500 --quiet 1 --mode snapshot --storage local --compress zstd --keep-last 3 --mailnotification failure"
  }

  connection {
    type  = "ssh"
    host  = var.proxmox_host
    user  = var.proxmox_ssh_user
    agent = true
  }

  provisioner "remote-exec" {
    inline = [
      "CONFIG=/etc/pve/vzdump.cron",
      "echo '# Managed by Terraform' > $CONFIG.tmp",
      "echo 'PATH=\"/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\"' >> $CONFIG.tmp",
      "echo \"\" >> $CONFIG.tmp",
      "echo '${self.triggers.cron_line}' >> $CONFIG.tmp",
      "mv $CONFIG.tmp $CONFIG",
      "systemctl restart cron || systemctl restart crond || true"
    ]
  }
}
