# fxEA - Fully Automated FX Trading EA

MT4上で動作する**完全自動FX取引EA**。

## コンセプト

> **autoEAの「負け方をコントロールする」思想を継承しつつ、エントリー判断も自動化**

### autoEAとの関係
- **autoEA**: 人間がエントリー判断、EAが執行・管理（ハイブリッド型）
- **fxEA**: エントリー判断も含めて完全自動化

---

## 機能

### エントリーロジック（新規）
- **MAクロス戦略**: EMA10/30のゴールデンクロス/デッドクロス
- **トレンドフィルター**: EMA100で方向を確認
- **時間フィルター**: 取引時間の制限
- **ストラテジーパターン**: 戦略を差し替え可能な設計

### リスク管理（autoEAから継承）
- **Z方式SL**: HardSL（ブローカー）+ SoftSL（30分連続滞在で決済）
- **ブレークイーブン移動**: ATR×1.5の含み益で発動
- **部分利確**: 1R（初期リスク額）の利益で50%決済
- **トレーリングストップ**: 直近20本の安値に追従
- **タイムストップ**: 4時間経過でプラスでなければ決済
- **RiskGuard連携**: 日次/週次損失上限を尊重

### 資金管理
- 1トレード1%リスク（ハードSL基準）
- ATRベースのSL/TP自動計算

---

## ファイル構成

```
fxEA/
├── README.md
├── INSTALL.md
├── design/
│   └── design_v1.0.md
└── src/
    ├── experts/
    │   └── fxEA.mq4           # メインEA
    └── include/
        ├── Utils.mqh           # ユーティリティ関数
        ├── RiskManager.mqh     # リスク管理
        ├── PositionManager.mqh # ポジション管理
        ├── Strategy_Base.mqh   # 戦略インターフェース
        └── Strategy_MACross.mqh# MAクロス戦略
```

---

## 主要パラメータ

| パラメータ | デフォルト | 説明 |
|-----------|-----------|------|
| FastMAPeriod | 10 | 短期EMA |
| SlowMAPeriod | 30 | 長期EMA |
| SLAtrMultiplier | 2.0 | SL = ATR × 2.0 |
| TPAtrMultiplier | 3.0 | TP = ATR × 3.0 |
| RiskPercent | 1.0 | 1トレード1%リスク |
| UseTimeFilter | true | 時間フィルター |
| UseTrendFilter | true | トレンドフィルター |
| MagicNumber | 20260510 | EA識別番号 |

---

## 使い方

1. `INSTALL.md`に従ってファイルをMT4にコピー
2. MetaEditorでコンパイル
3. USDJPYのH1チャートにEAをアタッチ
4. 自動売買ボタンを有効化

---

## 注意事項

- **デモ口座で十分にテスト**してから本番使用
- **RiskGuard**と併用を推奨
- バックテストでパラメータを検証
- 小ロット（0.01）から開始

---

## MagicNumber

| EA | MagicNumber |
|----|-------------|
| fxEA | 20260510 |
| TradeManager (autoEA) | 20260508 |
| RiskGuard | 99990001 |

---

## ライセンス

個人使用のみ。商用利用禁止。
