---
title: 既知の制限
description: 正式版 rocky10.2-rpms-2026.1 に含まれないもの、検証していないもの、対応しないもの。
sidebar:
  order: 4
---

対象は正式版 `rocky10.2-rpms-2026.1` です。

## 含まれないもの

- **provider NIC の接続：** provider NIC を `br-ex` に**接続しません**。自分で接続するまで、provider ネットワークと Floating IP は物理 LAN に届きません。
- **その他のサービス：** Cinder（ボリューム）、Swift などは導入しません。
- **noVNC コンソール：** コンソールプロキシを導入しないため、Horizon のコンソールタブは使えません。対応は開発中です（[noVNC コンソール（開発中）](/ja/development/novnc/)）。
- **SELinux ポリシー：** OpenStack 用の SELinux ポリシーを導入せず、ホストを permissive に切り替えます。
- **ファイアウォール：** ホストのファイアウォールを自動では設定しません。API、RabbitMQ、OVN southbound、memcached は管理ネットワークで待ち受けるため、ノードは信頼できるネットワークに置いてください。
- **パッケージの署名：** RPM は GPG 署名されていません。追加するリポジトリは `gpgcheck=0` です。完全性は、Git タグ内の lock に固定した SHA-256 と RPM セット ID で確認します。

## 検証していないもの

- SELinux の enforcing
- パッケージのテストスイート（`%check`）
- テナントネットワーク以外の経路（物理 LAN、ホスト外からの Floating IP への到達）
- ライブマイグレーション
- 3 台以上のノード構成
- RHEL、AlmaLinux、CentOS 10 などのほかの EL10
- ファイアウォールが有効なホスト
- GitHub Release からの `github` 取得を、実機の Rocky Linux 10.2 で通しで実行すること（公開後の確認では、公開 asset のダウンロード、SHA-256、lock、インストーラーの取得経路の検査をオフラインで確認済み）

## 対応しないもの

- x86_64 以外のアーキテクチャ
- 動いているクラウドの RPM セットの切り替え（アップグレード）

## 受入試験と公開 RPM の対応

| 試験 | 使った RPM |
|---|---|
| All-in-one（2026-11-15、run s66r5c） | 公開 RPM と**同じバイト列** |
| Controller + Compute（2026-11-16、run s66r5d） | 同じソース・同じ 195 パッケージ版から作り直したビルド（バイト列は一致しない） |
