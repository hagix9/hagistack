---
title: Glance（イメージ）
description: OS イメージの一覧、詳細、登録、削除。
sidebar:
  order: 3
---

Glance は VM の起動元になる OS イメージを管理します。HAGISTACK は `cirros-0.6.3-x86_64` を公開イメージとして登録します。

## 一覧と詳細

```bash
openstack image list
openstack image show cirros-0.6.3-x86_64
```

| 項目 | 内容 |
|---|---|
| 何を操作するか | 登録済みイメージの参照 |
| 期待される出力 | `cirros-0.6.3-x86_64` が `active`。`show` では `disk_format` が `qcow2`、`visibility` が `public`、プロパティ `hagistack_sha256` にアップロード前に検証したダイジェスト |
| 必要な権限 | 公開イメージは全ユーザーが参照可能 |
| Horizon | Project → Compute → Images |

## 登録する

qcow2 形式のイメージファイルを登録する例です。

```bash
openstack image create --disk-format qcow2 --container-format bare \
    --file ./my-image.qcow2 my-image
```

- `--public` を付けると全プロジェクトから使える公開イメージになります（管理者のみ）。付けない場合は、現在のプロジェクトだけで使えます。
- イメージは入手元が公開しているチェックサムで、登録前に検証してください（例：`sha256sum my-image.qcow2`）。
- ディスク容量に注意してください。イメージは controller のディスク（Glance の保存先）に置かれます。

## 削除する

```bash
openstack image delete my-image
```

:::danger
削除は取り消せません。`cirros-0.6.3-x86_64` を削除すると、HAGISTACK を再実行したときに再度ダウンロードして登録されます。
:::
