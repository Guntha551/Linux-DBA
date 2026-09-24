# 07 · Networking

**Goal:** Diagnose "cannot connect to the database" and slow-network problems, from the client all the way to the listener.

Default ports: **Oracle 1521**, **PostgreSQL 5432**, **MySQL 3306**, SSH 22.

---

## Step 1 — Interfaces and IP addresses

```bash
$ ip -br addr                  # brief list of interfaces and IPs
$ ip addr show eth0
$ ip route                     # routing table / default gateway
$ nmcli dev status             # NetworkManager view
```

---

## Step 2 — Is the database listening?

```bash
# ss -tlnp                           # TCP, listening, numeric, with process
# ss -tlnp | grep -E '1521|5432|3306'
LISTEN 0 128  0.0.0.0:5432  0.0.0.0:*  users:(("postgres",pid=1234,fd=6))
```

- `0.0.0.0:5432` / `*:5432` → listening on all interfaces (remote clients can connect).
- `127.0.0.1:5432` → **local only**. Fix `listen_addresses` (PostgreSQL) or `bind-address` (MySQL).

Older systems: `netstat -tlnp`.

---

## Step 3 — Can the client reach the port?

Run from the **client/app server**:

```bash
$ ping -c 4 dbhost01                 # basic reachability (ICMP may be blocked)
$ nc -zv dbhost01 1521               # TCP port test
$ timeout 3 bash -c '</dev/tcp/dbhost01/5432' && echo open || echo closed   # no extra tools needed
$ telnet dbhost01 3306
$ tnsping ORCL                       # Oracle: resolves TNS alias and contacts the listener
$ pg_isready -h dbhost01 -p 5432     # PostgreSQL
$ mysqladmin -h dbhost01 -u app -p ping
```

| Result | Likely cause |
|--------|--------------|
| `Connection refused` | Host reachable, nothing listening on that port / wrong IP bound |
| `Connection timed out` / no response | Firewall (host `firewalld` or network) dropping packets |
| `Name or service not known` | DNS / `/etc/hosts` problem |

---

## Step 4 — Name resolution

```bash
$ getent hosts dbhost01          # what the system resolver returns (uses /etc/hosts + DNS)
$ nslookup dbhost01
$ dig +short dbhost01
$ cat /etc/hosts /etc/resolv.conf
```

Oracle RAC / Data Guard are very sensitive to hostname resolution — the host's own name must resolve to its public IP.

---

## Step 5 — Current connections to the database

```bash
$ ss -tnp state established '( sport = :5432 )'       # sessions connected to PostgreSQL
$ ss -tn state established '( sport = :1521 )' | awk 'NR>1{split($4,a,":");print a[1]}' | sort | uniq -c | sort -nr
#   -> number of connections per client IP to the Oracle listener
$ ss -s                                                  # socket summary
$ ss -tan | awk '{print $1}' | sort | uniq -c            # counts per TCP state (TIME-WAIT, CLOSE-WAIT...)
```

Many `CLOSE-WAIT` sockets = application not closing connections properly.

---

## Step 6 — Path and latency

```bash
$ traceroute dbhost01            # hops between client and server
$ mtr -rwc 50 dbhost01           # loss/latency per hop over 50 probes
$ ping -M do -s 8972 dbhost02    # test jumbo frames (MTU 9000) on the RAC interconnect / DG link
```

---

## Step 7 — Bandwidth and interface errors

```bash
$ ip -s link show eth0           # RX/TX errors and drops
$ ethtool eth0                   # speed / duplex (1000Mb/s Full?)
$ sar -n DEV 5 3                 # throughput per interface
$ iperf3 -s                      # on server
$ iperf3 -c dbhost01 -P 4        # on client: measures real bandwidth (useful before a big Data Guard / replica sync)
```

---

## Step 8 — Capture packets (advanced)

```bash
# tcpdump -i eth0 port 5432 -nn -c 100
# tcpdump -i eth0 host 10.0.0.25 and port 1521 -w /tmp/ora.pcap   # open later in Wireshark
```
