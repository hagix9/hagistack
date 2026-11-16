---
title: トラブルシューティング
description: インストール、Horizon、VM、Compute ノード追加でよくある問題と確認手順。
sidebar:
  order: 3
---

## インストール

| 症状 | 原因と対処 |
|---|---|
| `no published RPM release is pinned` | タグ `rocky10.2-rpms-2026.1` より古いチェックアウトです。正式タグを clone し直すか、`--rpm-source build` か `--repo-url` を使います |
| ダウンロードや検証に失敗する | 何もインストールされていません。ネットワークを確認して再実行します。ビルドへは自動で切り替わりません |
| `Switching the package set of a running cloud is an upgrade` | このホストは別の RPM セットで導入済みです。HAGISTACK はアップグレードを行いません |
| `delorean-component-*` が有効という警告 | `dnf config-manager --set-disabled 'delorean-component-*'` で無効にします。有効なままだと単一のリリースになりません |
| `error:` の行なしで止まる | 出力の最後の `==>` の行が失敗したフェーズです |
| `INCOMPLETE — these phases were skipped` | 表示されたフェーズの原因を直して再実行します |

## Horizon にアクセスできない

1. URL が `http://管理IP/dashboard/` か確認します（末尾の `/dashboard/` が必要です）。
2. controller で httpd が動いているか確認します。

   ```bash
   systemctl status httpd
   curl -s -o /dev/null -w '%{http_code}\n' http://管理IP/dashboard/auth/login/
   ```

   `200` が返れば Horizon は応答しています。
3. ブラウザから管理 IP の 80 番ポートに届くか確認します。`firewalld` が有効な場合は 80/tcp を開ける必要があります（HAGISTACK はファイアウォールを設定しません）。
4. パスワードは `/etc/hagistack/admin-openrc` の `OS_PASSWORD` です。
5. `sudo ./tests-horizon-login.sh` で、サインインをコマンドラインから確認できます。

## VM が起動しない（ERROR）

```bash
openstack server show VM_NAME -c status -c fault
openstack compute service list
openstack hypervisor list
```

| `fault` の内容 | 対処 |
|---|---|
| `No valid host was found` | 動いている Compute がない、または空きリソースが足りない。`compute service list` で `nova-compute` が `up` か確認。controller 単独構成では Compute ノードを追加するまで VM は起動できません |
| `Refusing to bind port … no OVN chassis for host` | Nova のホスト名と OVN の chassis 名が一致していません。各ノードのホスト名が一意で安定しているか確認して再実行します |

Compute ノードのログ：

```bash
journalctl -u openstack-nova-compute -n 200
journalctl -u neutron-ovn-metadata-agent -n 100
```

## SSH で接続できない

1. VM が `ACTIVE` か確認します。
2. 起動ログで、cloud-init が鍵を取得できたか確認します。

   ```bash
   openstack console log show VM_NAME | tail -40
   ```

3. セキュリティグループに TCP 22 の ingress ルールがあるか確認します（[最初の VM](/ja/quickstart/first-vm/#16-セキュリティグループを確認する)）。
4. 接続経路を確認します。Floating IP は、そのままでは物理 LAN から届きません。テナントアドレスに metadata 名前空間から接続する方法か、ホストの `br-ex` にゲートウェイアドレスを付ける方法を使います（[最初の VM](/ja/quickstart/first-vm/#17-ssh-で-vm-にログインする)）。
5. ユーザー名は `cirros`、鍵は `/etc/hagistack/hagistack-key` です。

## Compute ノードの追加

[Compute ノードの追加のトラブルシューティング](/ja/guides/add-compute/#9-トラブルシューティング) を参照してください。

## 情報を集める

問題を報告するときは、パスワードや鍵を含めないでください。`admin-openrc`、`secrets.env`、`compute-secrets.env`、`hagistack-key` は共有しないでください。

```bash
sudo ./hagistack status
journalctl -u UNIT_NAME -n 200 --no-pager
```
