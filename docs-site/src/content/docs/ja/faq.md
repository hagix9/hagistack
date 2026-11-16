---
title: よくある質問
description: インストール要件、GCE とオンプレミス、Horizon、VM、SSH、noVNC についての質問。
---

## インストールに必要なものは？

Rocky Linux 10.2（x86_64）を入れたホスト、`sudo` の権限、8 GB 以上のメモリ、`/` に 20 GB 以上の空き、provider NIC として指定する実在のインターフェース、provider ネットワークの値（CIDR、ゲートウェイ、Floating IP の範囲）、インターネット接続です。詳しくは [インストール前の準備](/ja/quickstart/prepare/) を参照してください。

## OpenStack の RPM を自分でビルドする必要はありますか？

ありません。正式版では、インストーラーが GitHub Releases からビルド済みの RPM を取得して検証します。ソースからビルドしたい場合だけ `--rpm-source build` を使います（数時間かかります）。

## GCE とオンプレミスで何が違いますか？

- **GCE：** VM の中で VM を動かすため、ネスト仮想化を有効にしたインスタンスが必要です。ノード間の通信は VPC のファイアウォールルールで許可します。HAGISTACK の受入試験は GCE（ネスト KVM）で行っています。
- **オンプレミス：** BIOS/UEFI で仮想化支援を有効にします。ノード間のファイアウォールやスイッチで必要なポートを通します。物理 LAN から Floating IP に届くようにするには、provider NIC を `br-ex` に自分で接続する必要があり、この構成は検証していません。

## Horizon にアクセスできません

URL は `http://管理IP/dashboard/` です。httpd が動いているか、ブラウザから管理 IP の 80 番に届くか（`firewalld` など）を確認してください。詳しくは [トラブルシューティング](/ja/operations/troubleshooting/#horizon-にアクセスできない) を参照してください。

## VM が起動しません

`openstack server show VM_NAME -c fault` でエラーを確認します。`No valid host was found` の場合は、`nova-compute` が `up` か、空きリソースが足りているかを確認してください。[トラブルシューティング](/ja/operations/troubleshooting/#vm-が起動しないerror) を参照してください。

## VM に SSH できません

Floating IP は、そのままでは物理 LAN から届きません。テナントアドレスに metadata 名前空間から接続する方法か、ホストの `br-ex` に provider ゲートウェイのアドレスを付ける方法を使ってください（[最初の VM](/ja/quickstart/first-vm/#17-ssh-で-vm-にログインする)）。ユーザー名は `cirros`、鍵は `/etc/hagistack/hagistack-key` です。

## noVNC コンソールは使えますか？

**正式版 `rocky10.2-rpms-2026.1` では使えません。** Horizon のコンソールタブは動作しません。
noVNC 対応は次の修正版に向けて開発中で、実環境での受入試験はまだ行っていません（[noVNC コンソール（開発中）](/ja/development/novnc/)）。

## Compute ノードは何台まで追加できますか？

`compute-add` は繰り返し実行できますが、検証済みなのは Compute ノード 1 台の追加（2 台構成）までです。3 台以上の構成は検証していません。

## SELinux を enforcing にできますか？

検証していません。HAGISTACK は SELinux を permissive に切り替えます。OpenStack 用の SELinux ポリシー（`openstack-selinux`）は導入しません。
