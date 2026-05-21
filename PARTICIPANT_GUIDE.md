# Pinyintone 使用说明 / Guide d'utilisation

面向被试。App 界面支持中/法/英/阿拉伯语，安装后可在「设置」里切换。
Pour les participant·e·s. L'app est en chinois / français / anglais / arabe (réglable dans Réglages).

---

## 中文

### 1. 安装
1. 打开研究者发给你的 **TestFlight 邀请链接**。
2. 按提示安装 **TestFlight**（App Store 免费），再在里面安装 **Pinyintone**。

### 2. 首次进入
1. 点「**允许麦克风**」（练习需要录音分析发音）。
2. 选择语言。
3. 选 **「我是学生」**。
4. 输入研究者发给你的 **6 位测试码**（必填），昵称可留空 → 继续。

### 3. 三个练习
- **送气训练**：对着麦克风用力送气，吹散蒲公英。
- **声调训练**：先点「**听样例**」听标准读音 → 按住录音念出来 → 看 **0–100 分**（60 分及以上为通过）。
- **自由文本练习**：粘贴/输入中文 → 自动分词 → 逐词练习；可点书签**收藏**词条，之后在「我的词条」复习。

### 4. 提示
- 在**安静环境**练习，手机麦克风对准嘴。
- 分数是发音与标准读音的接近度，多练会进步。
- **隐私**：不上传录音，只上传分析结果（分数等），用于研究。

---

## Français

### 1. Installation
1. Ouvrez le **lien d'invitation TestFlight** envoyé par le chercheur.
2. Installez **TestFlight** (gratuit), puis installez **Pinyintone** à l'intérieur.

### 2. Première ouverture
1. Touchez « **Autoriser le microphone** » (l'analyse de prononciation nécessite l'enregistrement).
2. Choisissez la langue.
3. Choisissez **« Je suis étudiant·e »**.
4. Saisissez le **code de test à 6 chiffres** remis par le chercheur (obligatoire) ; le surnom est facultatif → Continuer.

### 3. Les trois exercices
- **Aspiration** : soufflez fort dans le micro pour disperser le pissenlit.
- **Tons** : touchez « **Écouter** » pour le modèle → enregistrez en répétant → voyez le **score sur 100** (≥ 60 = réussi).
- **Texte libre** : collez/saisissez du chinois → segmentation automatique → entraînement mot par mot ; touchez le marque-page pour **enregistrer** un mot, puis le revoir dans « Mes mots ».

### 4. Conseils
- Pratiquez dans un **endroit calme**, micro près de la bouche.
- Le score mesure la proximité avec le modèle ; il s'améliore avec la pratique.
- **Confidentialité** : aucun enregistrement audio n'est envoyé, seulement les résultats d'analyse (scores), à des fins de recherche.

---

## 给研究者备注 / Note chercheur
- 发码分组：`1` 开头 = 组 A（静态色块）；`2` 开头 = 组 B（动态 F0）。每人可发不同尾号便于区分（如 `100001`、`100002` / `200001`、`200002`）。
- 数据导出见 `backend/analysis/export.sql`（按 `group_assignment` 拉 A/B 两组）。
