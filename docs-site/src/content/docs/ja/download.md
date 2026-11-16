---
title: ダウンロード
description: 正式版 rocky10.2-rpms-2026.1 の GitHub Release、RPM・SRPM、対応 OS とアーキテクチャ、リリースノート。
---

## 正式版

| 項目 | 内容 |
|---|---|
| リリース名 | Hagistack for Rocky Linux 10.2 — OpenStack 2026.1 |
| タグ | `rocky10.2-rpms-2026.1` |
| GitHub Release | [github.com/hagix9/hagistack/releases/tag/rocky10.2-rpms-2026.1](https://github.com/hagix9/hagistack/releases/tag/rocky10.2-rpms-2026.1) |
| 対応 OS | Rocky Linux 10.2 |
| アーキテクチャ | x86_64 |
| OpenStack | 2026.1（Gazpacho） |

通常は RPM を手でダウンロードする必要はありません。インストーラーが取得・検証します。

```bash
git clone --branch rocky10.2-rpms-2026.1 https://github.com/hagix9/hagistack.git
```

## 配布ファイル

| ファイル | 内容 | SHA-256 |
|---|---|---|
| `hagistack-rpms-rocky10.2-rpms-2026.1-el10-x86_64.tar` | バイナリ RPM 195 個（すべて noarch）とリポジトリのメタデータ、`RPM-SHA256SUMS` | `565a10133cbb26b6f871f53514c7f8ebc0b3329c206a8b0ed7d2b93690ab713b` |
| `hagistack-srpms-rocky10.2-rpms-2026.1.tar` | ソース RPM 69 個（spec、上流のソース、パッチ、ライセンス） | `db019350729477a7f12d4cfed5dd067e813eb0158a3f5b19d5191785708fdd25` |
| `PACKAGE_MANIFEST.tsv` | RPM ごとの名前、版、ライセンス、ソース RPM、SHA-256 | `f49fe50bd263c5ddb3c411c6fc347da7c2a7ffddb4d03cffea47b4776bc483e6` |
| `rpm-release.lock.candidate` | タグ内の `rocky10.2/rpm-release.lock` と同一 | `9ff85a2a5fffcb32ac5d1f400e25a1164d22c04af8c89a22c902c959e4c00da4` |
| `SHA256SUMS` | 各ファイルの SHA-256 | `4bd30d36466e9ea43e7f5ea24d89c0f524edfc558fd950f18abba7728b5280df` |
| `LICENSE`、`THIRD_PARTY_NOTICES.md`、`RELEASE-README.md`、`gazpacho.manifest`、`build-env.lock` | ライセンス、第三者通知、説明、ビルド入力と環境 | — |

RPM セット ID（`RPM-SHA256SUMS` の SHA-256）：`0b61c809ad2e90d5ab07502ae0732aaf61475278b032585cc98d9418c1f62000`

## 手で検証する

```bash
sha256sum -c --ignore-missing SHA256SUMS
tar -xf hagistack-rpms-rocky10.2-rpms-2026.1-el10-x86_64.tar
( cd repo && sha256sum -c ../RPM-SHA256SUMS )
sha256sum RPM-SHA256SUMS
```

最後の値が、タグ内の `rocky10.2/rpm-release.lock` の `RPM_SET_SHA256` と一致することを確認します。
信頼の起点は、配布物の隣にある `SHA256SUMS` ではなく、**Git タグ内の lock** です。
`SHA256SUMS` に載っている `third-party/` のファイルは、タグ内の `rocky10.2/third-party/` と同一のため、Release には添付していません（そのため `--ignore-missing` を付けます）。

## ライセンス

- HAGISTACK 自身のコード：MIT License（`LICENSE`）
- RPM に含まれるソフトウェア：それぞれのライセンス（主に Apache License 2.0）。`THIRD_PARTY_NOTICES.md`、`PACKAGE_MANIFEST.tsv` の License 列、ソース RPM を参照してください。
- 上流のソースに加えた変更は `THIRD_PARTY_NOTICES.md` にまとめ、各パッケージの `/usr/share/hagistack/changes/<package>/HAGISTACK-CHANGES` にも入っています。
- HAGISTACK は OpenStack Foundation のリリースではありません。商標の扱いは `THIRD_PARTY_NOTICES.md` を参照してください。

## リリースノート

リリースノートは [GitHub Release](https://github.com/hagix9/hagistack/releases/tag/rocky10.2-rpms-2026.1) にあります。主な内容：

- 検証した構成と、公開 RPM と受入試験の対応
- 既知の制限（RPM 未署名、SELinux permissive、ファイアウォールの自動設定なし、ライブマイグレーション未検証、3 台以上未検証、x86_64 と Rocky Linux 10.2 のみ）
