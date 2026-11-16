---
title: Placement（リソース管理）
description: リソースプロバイダーとリソース割り当ての考え方と、HAGISTACK で確認できる方法。
sidebar:
  order: 6
---

Placement は、各 Compute ホストが持つリソース（vCPU、メモリ、ディスク）と、VM による使用量を記録するサービスです。

- **リソースプロバイダー：** Compute ホストごとに 1 つ作られます（例：Node 1、Node 2）。
- **インベントリ：** プロバイダーが持つリソースの総量（`VCPU`、`MEMORY_MB`、`DISK_GB`）。
- **割り当て（allocation）：** VM が使っている量。Nova スケジューラーは、Placement の空き状況を見て配置先の候補を決めます。

## HAGISTACK での確認方法

`openstack resource provider list` などの Placement 用サブコマンドは、別のプラグイン（osc-placement）で提供されます。
**HAGISTACK はこのプラグインを導入しません。** そのため、次の 2 つの方法で確認します。

### ハイパーバイザから確認する

```bash
openstack hypervisor list
openstack hypervisor show HYPERVISOR_HOSTNAME
```

Compute ホストの一覧と状態を確認できます。

### Placement API を直接読む

受入試験で Placement の状態を確認したのと同じ方法です。admin の認証情報を読み込んだ root シェルで実行します。

```bash
URL=$(openstack endpoint list --service placement --interface public -f value -c URL | head -1)
TOKEN=$(openstack token issue -f value -c id)
curl -s -H "X-Auth-Token: $TOKEN" -H 'OpenStack-API-Version: placement 1.0' \
    "$URL/resource_providers" | python3 -m json.tool
```

**期待される結果：** `resource_providers` に Compute ホストごとのプロバイダーが並びます。

:::caution[トークンの扱い]
`TOKEN` は admin のトークンです。画面共有やログに出さないでください。有効期限が来るまで使えます。
:::

インベントリを見る場合は、プロバイダーの `uuid` を使います。

```bash
curl -s -H "X-Auth-Token: $TOKEN" -H 'OpenStack-API-Version: placement 1.0' \
    "$URL/resource_providers/PROVIDER_UUID/inventories" | python3 -m json.tool
```

Horizon には Placement 専用の画面はありません。Admin → Compute → Hypervisors で、ホストごとの使用量の概要を確認できます。
