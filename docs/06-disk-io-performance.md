# 06 · Disk I/O Performance

**Goal:** Prove (or disprove) that storage is the bottleneck, and find which device and process is responsible.

Install tools first: `# dnf install -y sysstat iotop` (RHEL) or `# apt install -y sysstat iotop` (Ubuntu).

---

## Step 1 — Is there I/O wait at all?

```bash
$ vmstat 2 5            # look at 'b' (blocked procs) and 'wa' (I/O wait %)
$ top                   # 'wa' in the %Cpu line
```

`wa` consistently above ~10–20% together with high `b` means processes are waiting on disk.

---

## Step 2 — Per-device statistics with iostat

```bash
$ iostat -xz 5 3        # extended stats, hide idle devices, 5s interval, 3 samples
$ iostat -xmtz 5        # MB/s and timestamps
```

```
Device  r/s   w/s   rMB/s  wMB/s  r_await  w_await  aqu-sz  %util
sdb    850.0 120.0  52.3    8.1     12.40     2.10    11.2   99.8
```

| Column | Meaning | Rough healthy value |
|--------|---------|---------------------|
| `r/s`, `w/s` | IOPS | depends on storage |
| `rMB/s`, `wMB/s` | throughput | depends on storage |
| `r_await`, `w_await` | avg latency in ms (includes queue time) | SSD < 1–2 ms, SAN < 5–10 ms |
| `aqu-sz` | average queue length | high = requests piling up |
| `%util` | time device was busy | ~100% on a single HDD = saturated (less meaningful for SSD/SAN arrays) |

**Tip:** The first sample of `iostat` shows averages since boot — ignore it.

---

## Step 3 — Map device names to mount points

```bash
$ lsblk -o NAME,KNAME,SIZE,TYPE,MOUNTPOINT
$ ls -l /dev/mapper/            # LVM dm-X names
$ dmsetup ls
```

`iostat` often prints `dm-3`; `lsblk` tells you that `dm-3` is `vg_data-lv_u02` → `/u02`.

---

## Step 4 — Which process is doing the I/O?

```bash
# iotop -oPa            # only active processes, per-process, accumulated totals
$ pidstat -d 5 3        # per-process read/write kB/s
# cat /proc/<PID>/io    # cumulative bytes read/written by a process
```

---

## Step 5 — Quick throughput tests

```bash
# write 2 GB bypassing the page cache
$ dd if=/dev/zero of=/u02/ddtest bs=1M count=2048 oflag=direct
# read it back
$ dd if=/u02/ddtest of=/dev/null bs=1M iflag=direct
$ rm /u02/ddtest
```

For database-like random I/O, use `fio`:

```bash
$ fio --name=randrw --directory=/u02 --rw=randrw --rwmixread=70 --bs=8k \
      --size=2G --numjobs=4 --iodepth=32 --ioengine=libaio --direct=1 \
      --runtime=60 --time_based --group_reporting
```

`bs=8k` matches the Oracle/PostgreSQL block size; `16k` matches InnoDB. **⚠️** Do not benchmark on a busy production disk.

---

## Step 6 — I/O scheduler

```bash
$ cat /sys/block/sdb/queue/scheduler
[mq-deadline] kyber bfq none
# echo none > /sys/block/sdb/queue/scheduler     # NVMe/SSD/SAN: 'none' or 'mq-deadline'
```

Make it persistent with a udev rule or `tuned` profile (chapter 09).

---

## Step 7 — Read-ahead

```bash
# blockdev --getra /dev/sdb         # in 512-byte sectors
# blockdev --setra 4096 /dev/sdb    # larger read-ahead helps full scans / backups
```

---

## Step 8 — Historical data

```bash
$ sar -d -p 5 3                                 # device stats now
$ sar -d -p -f /var/log/sa/sa15                 # device stats for the 15th of the month
$ sar -b                                        # overall I/O rates
```

Check that `sysstat` collection is enabled: `# systemctl enable --now sysstat`.
