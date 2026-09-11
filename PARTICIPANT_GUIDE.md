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
4. 选 **「我是学生」** → 用 **Apple 账号登录** → 名字**可留空**（Apple 通常会自动填好，也可以自己改；之后随时能在「设置」里改）→ 继续。无需任何测试码。

### 3. 三个练习
- **送气训练**：对着麦克风用力送气，吹散蒲公英。
- **声调训练**：分三个阶段（见下）。先点「**听样例**」听标准读音 → 录音念出来。
- **自由文本练习**：粘贴/输入中文 → 自动分词 → 逐词练习；可点书签**收藏**词条，之后在「我的词条」复习。

### 3b. 声调训练的三个阶段
1. **前测**：4 个词各录一遍。**这一轮不会显示分数、颜色或曲线**——
   这是研究设计，不是 App 坏了。请按你现在的读法读。录完自动跳下一题。
2. **训练**：会显示反馈，看到 **0–100 分**（60 分及以上为通过），可以重录也可以换词。
   反馈有两种显示方式——**颜色块**或**音高曲线**——在「设置 → 反馈显示方式」里
   随时可换，两种的通过标准完全一样，换了不影响分数。
3. **后测**：练过一轮后页面会出现「**开始后测**」。和前测一样只录音，不显示分数。

> 如果提示「没听清，请靠近麦克风重录」——那是**录音没录好**，不是你读错了。
> 这类情况不会计入成绩，重录一次即可。

### 4. 提示
- 在**安静环境**练习，手机麦克风对准嘴。
- 分数是发音与标准读音的接近度，多练会进步。
- **隐私**：录音只在你的手机上分析音高，**原始音频不会上传、不会存到服务器**；
  只有分析结果（分数与音高曲线）匿名上传，用于本项目的教学研究。
  你可以随时在「设置 → 删除账号」抹除全部数据（等同于撤回参与同意）。

---

## Français

### 1. Installation
1. Ouvrez le **lien d'invitation TestFlight** envoyé par le chercheur.
2. Installez **TestFlight** (gratuit), puis installez **Pinyintone** à l'intérieur.

### 2. Première ouverture
1. Touchez « **Autoriser le microphone** » (l'analyse de prononciation nécessite l'enregistrement).
2. Choisissez la langue.
3. Choisissez **« Je suis étudiant·e »**.
4. Choisissez **« Je suis étudiant·e »** → connectez-vous avec **votre compte Apple** → le nom est **facultatif** (Apple le remplit en général ; vous pouvez le modifier, y compris plus tard dans les Réglages) → Continuer. Aucun code n'est nécessaire.

### 3. Les trois exercices
- **Aspiration** : soufflez fort dans le micro pour disperser le pissenlit.
- **Tons** : en trois phases (ci-dessous). Touchez « **Écouter** » pour le modèle → enregistrez en répétant.
- **Texte libre** : collez/saisissez du chinois → segmentation automatique → entraînement mot par mot ; touchez le marque-page pour **enregistrer** un mot, puis le revoir dans « Mes mots ».

### 3b. Les trois phases de l'exercice de tons
1. **Pré-test** : 4 mots, un enregistrement chacun. **Aucun score, aucune couleur, aucune courbe**
   — c'est voulu, l'app ne bugue pas. Prononcez comme vous le faites aujourd'hui. Passage automatique au mot suivant.
2. **Entraînement** : votre courbe de hauteur s'affiche à côté de celle du modèle,
   avec un **score sur 100** (≥ 60 = réussi). Vous pouvez réenregistrer ou changer de mot.
3. **Post-test** : après un tour d'entraînement, le bouton « **Commencer le post-test** » apparaît.
   Comme le pré-test : enregistrement seul, sans score.

> Le message « Je n'ai pas bien entendu » signale un **problème d'enregistrement**, pas une erreur de prononciation.
> Ces essais ne comptent pas dans les résultats : réenregistrez simplement.

### 4. Conseils
- Pratiquez dans un **endroit calme**, micro près de la bouche.
- Le score mesure la proximité avec le modèle ; il s'améliore avec la pratique.
- **Confidentialité** : votre enregistrement est analysé sur votre téléphone ; **l'audio brut n'est jamais envoyé ni conservé sur un serveur**. Seuls les résultats d'analyse (score et courbe de hauteur) sont transmis de façon anonyme, à des fins de recherche pédagogique. Vous pouvez tout supprimer à tout moment via « Réglages → Supprimer le compte » (équivalent à un retrait du consentement).

---

## 给研究者备注 / Note chercheur
- **已取消 A/B 分组**：两种反馈显示方式由被试自选（设置里可换），不是随机分组，无需发码。
  `feedback_mode` 只描述"当时屏幕上是哪种"，**不可当实验条件比较**。
- `phase` 用来区分前测 / 训练 / 后测；`schema_version >= 3` 即代表动态曲线呈现。
  带 `staticColor` / `dynamicF0` 的是取消分组之前的历史数据，不可与新数据混比。
- 数据导出见 `backend/analysis/export.sql`（第 3 段前后测；用 `nickname` 对回个人）。
- 提醒被试：前测/后测不显示分数是**设计如此**，否则他们会以为 App 出故障并反复重录。
