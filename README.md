# Zrepl Sink TLS Client Configuration

An Ansible role to provide an automated _ZREPL Sink Client_ templated deployment.

---

## TL;DR

* This does not install the Zrepl client, existing installation is required
* This does not create/generate the TLS certificates
  * Does push TLS certificates needed by the client to connect to the sink server
* Uses a templated configuration but not designed to support unique per instance configurations
  * Intended to be used for pushing out a common baseline sink configuration
  * Usually only a single Zrepl sink job is required, examples here show two sink jobs:
    1) One for ZFS datasets
    2) Another for ZFS ZVOLs (requires different attribute settings)
* Some per host settings can be defined via Ansible inventory or other ansible methods to override defaults
  * ZFS pool name, encrypted send, bandwidth limits
* Clients can be easily configured to enable Prometheus metrics
  * You then define your own scrape job on Prometheus to collect metrics.
* A Threshold script is provided which can be used to:
  * Prevent Zrepl from creating zero-byte snapshots
  * Or set a minimum size of bytes change to a dataset before a new snapshot is taken
  * Some people consider hundreds of small or zero-byte snapshots to be wasteful
  * _NOTE: When a snapshot creation is denied, Zrepl logs this as a fatal error, it does not allow a way to report a non-fatal reason for refusing a snapshot. The error is harmless, but spams system logs._

---

## Requirements

* Target computers with Zrepl client already installed
* [Generate TLS certificates](https://github.com/reefland/zrepl_sink/blob/main/docs/ca_using_easyrsa.md) for each client and sink server
* Pre-existing [Zrepl sink server](https://github.com/reefland/zrepl_sink) to connect with

---

## Packages Installed

* none

---

## How Do I Set It Up

### Edit your inventory document

You can design your inventory file as you see fit, I like to use `yaml` format such as:

```yaml
zrepl_sink_tls_client_group:
  hosts:
    k3s[01:03].mydomain.com:
      zrepl_zfs_pool_name: "rpool"
      zrepl_filesystems: |
        "{{ zrepl_zfs_pool_name }}/ROOT<": true,
        "{{ zrepl_zfs_pool_name }}/USERDATA<": true,

    k3s[04:06].mydomain.com:
      zrepl_zfs_pool_name: "{{ ansible_hostname }}"
      zrepl_filesystems: |
        "{{ zrepl_zfs_pool_name }}/ROOT<": true,

    k3s[01:05].mydomain.com:
      zrepl_send_bandwidth_limit: "15 MiB"

  vars:
    zrepl_sink_server: "truenas.mydomain.com:9448"
    enable_prometheus: true
```

* Hosts k3s01 through k3s03 use ZFS pool name `rpool`, whereas k3s04 through k3s06 use pool names matching the hostname.
* The filesystems to replicate use the standard zrepl conventions
* Hosts k3s01 - k3s05 have a `15 MiB` replication limit set, whereas k3s06 has no restriction and can replicate at full link speed
* The `zrepl_sink_server` defines the hostname and port of the Zrepl sink server make a TLS connection with. I have it running on my TrueNAS Scale server.
* The `enable_prometheus` configures the client to expose Prometheus metrics

---

### Review `defaults/main.yml` to define the defaults

The `defaults/main.yml` can be used to configure the default values including multiple sink jobs for the client.  These defaults can be overwritten by any of the typical Ansible variable methods such as using inventory variables.

#### Generic Zrepl Sink Settings

```yaml
# Define location to store zrepl.yml and TLS certificates
zrepl_config_path: "/etc/zrepl"

# Should Prometheus stanza in zrepl.yml be included
enable_prometheus: true

# Should Threshold Script be enabled
enable_threshold_script: false

# Default Name and port of remote Zrepl Sink Server
zrepl_sink_server: "zrepl.local:9448"

# Default Name of ZFS zpool to work with
zrepl_zfs_pool_name: "rpool"

# Define bandwidth replication limit when sending
# Examples: "10 MiB", "23.5 MiB", or disable: "-1 MiB"
zrepl_send_bandwidth_limit: -1 MiB
```

|Variable Name| Default Value | Comments|
|---          |---            |---      |
|`zrepl_config_path` | "/etc/zrepl" | Location to find existing Zrepl configuration file to replace |
|`enable_prometheus` | `true` | Boolean value if the Prometheus metrics should be enabled or not |
|`enable_threshold_script` | `false` | Boolean value if the threshold script is enabled |
|`zrepl_sink_server` | "zrepl.local:9448" | Fully qualified domain name and port of Zrepl Sink Server instance |
|`zrepl_zfs_pool_name` | "rpool" | Default ZFS pool name to use |
|`zrepl_send_bandwidth_limit` | -1 MiB | Replication send bandwidth limit for client, `-1 MiB` disables send limit |

#### Define TLS Certificate Naming Convention

```yaml
# Define Client TLS Certificate Names
zrepl_tls_ca_crt_name: "ca.crt"
zrepl_tls_cert_name: "{{ ansible_hostname }}.crt"
zrepl_tls_private_key_name: "{{ ansible_hostname }}.key"
zrepl_tls_server_cn: "sink-srv"
```

|Variable Name| Default Value | Comments|
|---          |---            |---      |
|`zrepl_tls_ca_crt_name` | "ca.crt" | Name of the certificate authority signing certificate |
|`zrepl_tls_cert_name` | "`{{ ansible_hostname }}.crt`" | Client certificate name |
|`zrepl_tls_private_key_name` | "`{{ ansible_hostname }}.key`" | Client private key name |
|`zrepl_tls_server_cn` | "sink-srv" | Value in the CN attribute within certificate used on Sink Server |

---

### Define Zrepl Snapshot Replication Jobs

`zrepl_snapjobs` contains a named yaml list of one of more jobs to create on each client. Ideally you just need a single job for `datasets` and an optional second one for `ZVOLs` as they have different properties.

#### Define Filesystems to Process

```yaml
zrepl_snapjobs:
  - name: rancher           # snapjob_rancher
    filesystems: |
      "{{ zrepl_zfs_pool_name }}/rancher<": true,
```

* Follows normal patterns used in [zrepl filesystem filters](https://zrepl.github.io/configuration/filter_syntax.html#fine-grained)

#### Define Send Options

```yaml
    send_options: |
      encrypted: true
      send_properties: false
      bandwidth_limit:
        max: {{ zrepl_send_bandwidth_limit }}
```

* Follows normal [zrepl send options](https://zrepl.github.io/configuration/sendrecvoptions.html#send-options)
* See Zrepl Project on [bandwidth limits](https://zrepl.github.io/configuration/sendrecvoptions.html#bandwidth-limit-send-recv) notes
* IMPORTANT: Keep `send_properties: false`. Setting this to true can result in sink server issues / unbootable. This prevents sink server and its host mounts from getting clobbered.

#### Define Replication Options

```yaml
    replication_options: |
      protection:
        initial: guarantee_resumability
        incremental: guarantee_incremental
```

* Follows normal [zrepl replication options](https://zrepl.github.io/configuration/replication.html)

#### Define Snapshoting Options

```yaml
    snapshotting_options: |
      type: periodic
      interval: 10m
      prefix: zrepl_
      timestamp_format: dense
```

* Follows normal [zrepl periodic snapshoting options](https://zrepl.github.io/configuration/snapshotting.html#periodic-snapshotting)

#### Snapshot Pruning Options

This sections allows different policies for local (`keep_sender`) vs. remote sink server (`keep_receiver`) snapshot retention.  The sink server typically has vast amount of storage and can retain snapshots much longer.

You can define multiple [zrepl pruning policies](https://zrepl.github.io/configuration/prune.html) for each `keep_sender` and `keep_receiver`.

```yaml
    pruning_options: |
      keep_sender:
        # fade-out scheme for snapshots
        # - keep all created in the last hour
        # - then destroy snapshots such that we keep 6 each 1 hour apart
        # - then destroy snapshots such that we keep 1 each 1 day apart
        # - then destroy all older snapshots
        - type: grid
          grid: 1x1h(keep=all) | 6x1h | 1x1d
          regex: "^zrepl_.*"
        # keep all snapshots that don't have the `zrepl_` prefix.
        - type: regex
          negate: true
          regex: "^(zrepl)_.*"
```

```yaml
    pruning_options: |
      keep_receiver:
        # Keep snapshots longer on sink server as it has more storage
        # keep all created in the last hour
        # keep 24 each 1 hour apart / keep 30 each 1 day apart / keep 4 each 30 days apart
        # then destroy all older snapshots
        - type: grid
          grid: 1x1h(keep=all) | 24x1h | 30x1d | 4x30d
          regex: "^zrepl_.*"
        # retain all non-zrepl snapshots on the sink server
        - type: regex
          negate: true
          regex: "^zrepl_.*"
```

---

## Running this playbook

This is an example playbook named `zrepl_sink_tls_client.yml`:

```yaml
---
- name: Update zrepl TLS Client for Sink Server Replication
  hosts: zrepl_sink_tls_client_group
  become: true
  gather_facts: true

  roles:
    - role: zrepl_sink_tls_client
```

```bash
# Apply playbook to all hosts defined in group
ansible-playbook -i inventory zrepl_sink_tls_client.yml

# Use Ansible's limit parameter to specify individual hostname to run on:
ansible-playbook -i inventory zrepl_sink_tls_client.yml -l testlinux.example.com
```
