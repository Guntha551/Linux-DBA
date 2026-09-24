# Linux for DBAs — One-Page Cheat Sheet

| Task | Command |
|------|---------|
| **System** | |
| OS version | `cat /etc/os-release` |
| Kernel | `uname -r` |
| Uptime & load | `uptime` |
| CPUs | `nproc` / `lscpu` |
| RAM | `free -h` |
| **Storage** | |
| Free space | `df -hT` |
| Inode usage | `df -i` |
| Largest dirs | `du -xh --max-depth=1 <dir> \| sort -hr \| head` |
| Files > 1 GB | `find <dir> -xdev -type f -size +1G -ls` |
| Deleted-but-open files | `lsof +L1` |
| Block devices | `lsblk -f` |
| LVM | `pvs; vgs; lvs` |
| Extend LV + FS | `lvextend -r -L +50G /dev/vg/lv` |
| **Performance** | |
| Overall | `vmstat 5 5` |
| Live processes | `top` (1 = per CPU, P = CPU, M = memory) |
| Per-CPU | `mpstat -P ALL 5` |
| Disk latency | `iostat -xz 5` |
| I/O per process | `iotop -oP` / `pidstat -d 5` |
| Top memory | `ps aux --sort=-rss \| head` |
| Top CPU | `ps -eo pid,user,%cpu,cmd --sort=-%cpu \| head` |
| History | `sar -u` / `sar -r` / `sar -d` |
| OOM kills | `dmesg -T \| grep -i 'killed process'` |
| **Processes** | |
| Oracle instances | `ps -ef \| grep [p]mon` |
| PostgreSQL | `ps -ef \| grep [p]ostgres` |
| MySQL | `pgrep -a mysqld` |
| Open files of PID | `lsof -p <PID>` |
| Limits of PID | `cat /proc/<PID>/limits` |
| Graceful kill | `kill <PID>` |
| Persistent session | `tmux new -s work` / `tmux attach -t work` |
| **Network** | |
| Listening ports | `ss -tlnp` |
| Test port | `nc -zv host 5432` |
| Connections per IP | `ss -tn state established '( sport = :1521 )'` |
| DNS | `getent hosts host` |
| Bandwidth | `iperf3 -c host` |
| **Logs** | |
| Follow log | `tail -F file` |
| Errors with context | `grep -B5 -A10 'ORA-00600' alert.log` |
| Count errors | `grep -o 'ORA-[0-9]\{5\}' alert.log \| sort \| uniq -c \| sort -nr` |
| System errors | `journalctl -p err -b` |
| Truncate open log | `> logfile` |
| **Kernel / limits** | |
| Kernel params | `sysctl -a \| grep -E 'shm\|sem'` |
| Apply params | `sysctl --system` |
| Shared memory | `ipcs -m` |
| HugePages | `grep Huge /proc/meminfo` |
| THP status | `cat /sys/kernel/mm/transparent_hugepage/enabled` |
| ulimits | `ulimit -a` |
| **Backup / transfer** | |
| Tar + gzip | `tar -czvf out.tar.gz <dir>` |
| Parallel gzip | `pigz -p 8 file` |
| Resumable copy | `rsync -avP src/ host:/dst/` |
| Checksum | `sha256sum file` / `sha256sum -c file.sha256` |
| SSH keys | `ssh-keygen -t ed25519 && ssh-copy-id user@host` |
| **Scheduling** | |
| Edit cron | `crontab -e` |
| Cron log | `grep CROND /var/log/cron` |
| Timers | `systemctl list-timers` |
| **Security** | |
| Open port | `firewall-cmd --permanent --add-port=5432/tcp && firewall-cmd --reload` |
| SELinux mode | `getenforce` |
| SELinux denials | `ausearch -m avc -ts recent` |
| Relabel dir | `semanage fcontext -a -t postgresql_db_t "/pgdata(/.*)?" && restorecon -Rv /pgdata` |
| **Services** | |
| Status | `systemctl status postgresql-16` |
| Service log | `journalctl -u mysqld -f` |
