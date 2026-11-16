---
title: noVNC コンソール（開発中）
description: Horizon の noVNC コンソール対応の開発状況。正式版 rocky10.2-rpms-2026.1 には含まれません。
---

:::caution[開発中の機能です]
noVNC コンソールは、正式版 `rocky10.2-rpms-2026.1` には**含まれません**。
次の Rocky Linux 10.2 修正版に向けて開発しており、**実環境での受入試験（ブラウザからの操作）はまだ行っていません。**
このページの内容は変わる可能性があります。
:::

## 現行の正式版の状態

正式版では、Nova の VNC サーバー設定は有効ですが、コンソールプロキシ（`openstack-nova-novncproxy`）とブラウザ側のクライアント（`novnc`）を導入していません。そのため Horizon の **コンソール** タブは動作しません。VM の状態は **ログ** タブ（`openstack console log show`）で確認してください。

## 開発中の構成

| 項目 | 内容 |
|---|---|
| controller | `openstack-nova-novncproxy`（HAGISTACK の RPM セットに含まれる）と `novnc`（RDO の依存リポジトリ）を導入し、プロキシを管理アドレスの TCP 6080 だけで待ち受ける |
| すべてのノード | `nova.conf` の `[vnc] novncproxy_base_url` を controller のプロキシ（`http://controller の管理IP:6080/vnc_lite.html`）に向ける |
| 接続の向き | ブラウザ → controller の 6080/tcp。プロキシ → ゲストが動く Compute ノードの VNC ポート（5900/tcp 以降） |
| RPM セット | 変更なし（新しい RPM は不要。インストーラーの変更だけ） |

## セキュリティ上の注意（開発中の構成）

- プロキシは平文の HTTP です。6080 番をインターネットに公開しないでください。管理ネットワークか VPN 経由で使います。HTTPS/WSS は設定していません。
- コンソール URL には一度だけ使えるトークンが含まれ、既定で 10 分で失効します。URL を共有しないでください。
- HAGISTACK はファイアウォールを設定しません。`firewalld` を使う場合は、controller の 6080/tcp を必要なブラウザにだけ、Compute ノードの 5900–5999/tcp を controller にだけ開けてください。
- SELinux はほかのサービスと同じく permissive です。

## 検証状況

| 項目 | 状況 |
|---|---|
| インストーラーの変更 | 開発ブランチで実装済み |
| ローカルの自動テスト | 実施済み（パッケージ構成、`nova.conf` の設定、待ち受けアドレス、再実行時に変更がないこと、プロキシの応答確認） |
| All-in-one での実環境の受入 | **未実施** |
| Controller + Compute での実環境の受入 | **未実施** |
| ブラウザからのコンソール操作 | **未実施** |

実環境での受入が完了するまで、この機能は正式な機能として扱いません。
