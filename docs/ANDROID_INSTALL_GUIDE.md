# Pinyintone Android 安装说明 · Guide d'installation · Guía de instalación · دليل التثبيت

> 给研究者的说明（参与者不用看这一段）：
> - Android 版不经过应用商店，参与者扫码下载安装包（`.apk`）自己安装。下载地址与二维码由研究者另行确定。
> - 本文的系统菜单名称按各厂商公开的设置路径写成，**还没有在真机上逐一核对**。所有「截图占位」都要在对应品牌的真机上拍摄后替换；
>   拍摄时顺便核对菜单名称，不一致的以真机为准改正文字。
> - 发给参与者时只发对应语言的那一节。
> - 支持的系统：Android 8.0 及以上。**HarmonyOS NEXT（鸿蒙 5）装不了**（它不再支持安卓安装包）。

---

## 中文

### 1. 先确认手机能装

- 需要 **Android 8.0 或更高版本**（设置 → 关于手机 里可以看到）。
- **华为手机如果是 HarmonyOS NEXT（鸿蒙 5，系统版本号 5.x，「关于手机」里写「HarmonyOS 5」）：装不了。**
  这一版鸿蒙不再支持安卓安装包，请联系研究者。HarmonyOS 2 / 3 / 4 可以装。
- 安装包大约 2 MB，用 Wi-Fi 或流量下载都可以。

### 2. 扫码下载

1. 用手机自带的**相机**或**浏览器**扫研究者给的二维码（微信「扫一扫」打开后，请点右上角「…」选「在浏览器打开」，微信里不能直接下载安装包）。
2. 浏览器打开下载页，点下载。文件名是 `pinyintone-版本号.apk`。
3. 如果浏览器提示「此类文件可能会损害设备」，选「仍然下载」或「下载」。
4. 下载完成后，点通知栏里的下载完成提示，或在浏览器的「下载」列表里点这个文件。

【截图占位：浏览器下载页与「仍然下载」提示，需用真机拍摄】

### 3. 允许「安装未知来源应用」

Android 8 以后，这个权限是**按应用**给的：你用哪个应用打开安装包（浏览器或「文件管理」），就给哪个应用开。
多数手机在你第一次点安装包时会自动弹出提示，点「设置」→ 打开「允许来自此来源的应用」→ 返回，就能继续安装。
如果没有弹出，按下面你的手机品牌操作。

#### 小米 / 红米：HyperOS

1. 点安装包后，如果提示「禁止安装未知来源应用」，点「设置」，打开「允许安装未知来源应用」。
2. 也可以手动去：设置 → 应用设置（或「应用」）→ 特殊权限（或「授权管理」）→ 安装未知应用 → 选你用的浏览器 → 打开开关。
3. 国内版 HyperOS 可能开着 **「纯净模式」**（设置 → 隐私与安全 / 安全，名称因版本不同）。安装时如果它拦下，选「仍然安装」或「仅本次允许」；
   有的版本需要等几秒的安全检查，看完提示后点「继续安装」。

【截图占位：小米 HyperOS 的「安装未知应用」开关与「纯净模式」提示，需用真机拍摄】

#### 小米 / 红米：MIUI（MIUI 12–14）

1. 设置 → 应用设置 → 应用管理 右上角「…」或「权限」→ 安装未知应用 → 选浏览器 → 打开「允许来自此来源的应用」。
2. 安装时 MIUI 会做安全扫描，可能要等几秒或要求登录小米账号；扫描完点「继续安装」。
   国内版如果有「纯净模式」，处理方法同上。

【截图占位：MIUI 的安全扫描页与「继续安装」按钮，需用真机拍摄】

#### 三星：One UI

1. 设置 → 应用程序 → 右上角「⋮」→ 特殊访问权限 → 安装未知应用程序 → 选你用的浏览器（Chrome、三星浏览器）或「我的文件」→ 打开「允许来自此来源」。
2. One UI 6 及以上如果打开了 **「自动拦截程序」**（设置 → 安全和隐私 → 自动拦截程序），会直接拦下所有安装包。
   需要先把它关掉，装好以后可以再打开。

【截图占位：三星「安装未知应用程序」与「自动拦截程序」开关，需用真机拍摄】

#### 华为：EMUI 与 HarmonyOS 2 / 3 / 4

1. 设置 → 安全 → 更多安全设置 → 安装外部来源应用 → 选你用的浏览器或「文件管理」→ 打开开关。
   （EMUI 较老的版本在：设置 → 安全和隐私 → 更多安全设置 → 安装未知应用。）
2. HarmonyOS 可能开着 **「纯净模式」**（设置 → 系统和更新 → 纯净模式）。安装时它会提示风险：点「仍然安装」，或先暂时退出纯净模式，装好再开。
3. **HarmonyOS NEXT（鸿蒙 5）装不了**，见第 1 步。

【截图占位：华为「安装外部来源应用」与「纯净模式」提示，需用真机拍摄】

### 4. 遇到安全警告怎么办

这个 App 没有上架应用商店，所以系统会提醒你「来源未知」。这是正常的，不代表 App 有问题。

- **Google Play 保护机制**提示「已阻止不安全的应用」或「未知的应用」：点「更多详情」→「仍然安装」。
  如果问要不要「发送应用以进行扫描」，选不发送也可以。
- **小米 / 华为的安全检测**提示「风险」：看完说明后点「仍然安装」或「继续安装」。
- 只安装**研究者给你的二维码**下载的文件。别人转发的安装包不要装。
- 如果提示「安装包已损坏」或「解析包时出现问题」：重新下载一次；仍然不行，告诉研究者你的手机型号和系统版本。

【截图占位：Google Play 保护机制「仍然安装」，需用真机拍摄】

### 5. 第一次打开

- 第一次点中间的麦克风按钮（「录音」）时，App 会先说明为什么要用麦克风，然后系统会问你，请选「允许」或「仅在使用该应用时允许」。
- 如果不小心拒绝了：App 里会出现「打开系统设置」的按钮，点它 → 权限 → 麦克风 → 允许。

### 6. 怎么更新

- 有新版本时，App 练习页顶部会出现提示，点「在浏览器中下载」，下载后像第一次一样点开安装即可。
- **直接覆盖安装，不要先卸载旧版本。** 卸载会删掉手机里还没上传的练习记录。
- 如果提示「请更新 App」：这个版本已经不再支持，请尽快更新；更新之前仍可以继续练习。
- 如果提示「应用未安装」或「与已安装的应用签名冲突」：说明你装的不是研究者发的版本，请联系研究者，不要自行卸载。

---

## Français

### 1. Vérifier que le téléphone est compatible

- Il faut **Android 8.0 ou plus récent** (Paramètres → À propos du téléphone).
- **Huawei avec HarmonyOS NEXT (HarmonyOS 5, « HarmonyOS 5.x » dans « À propos du téléphone ») : l'installation est impossible.**
  Cette version n'accepte plus les fichiers d'installation Android. Contactez le chercheur. HarmonyOS 2, 3 et 4 fonctionnent.
- Le fichier fait environ 2 Mo ; Wi-Fi ou données mobiles, au choix.

### 2. Scanner le QR code et télécharger

1. Scannez le QR code donné par le chercheur avec l'**appareil photo** ou le **navigateur** du téléphone
   (si vous l'ouvrez dans WhatsApp ou WeChat, choisissez « Ouvrir dans le navigateur » : ces applications ne permettent pas d'installer le fichier).
2. Sur la page qui s'ouvre, touchez « Télécharger ». Le fichier s'appelle `pinyintone-version.apk`.
3. Si le navigateur affiche « Ce type de fichier peut endommager votre appareil », choisissez « Télécharger quand même ».
4. Une fois le téléchargement terminé, touchez la notification, ou ouvrez le fichier depuis la liste des téléchargements du navigateur.

[Capture à insérer : page de téléchargement et message « Télécharger quand même » — à photographier sur un vrai téléphone]

### 3. Autoriser « Installer des applications inconnues »

Depuis Android 8, cette autorisation se donne **application par application** : on l'accorde à l'application qui ouvre le fichier
(le navigateur ou le gestionnaire de fichiers). La plupart des téléphones affichent un message la première fois : touchez « Paramètres »,
activez « Autoriser cette source », puis revenez en arrière pour continuer l'installation.
Si rien ne s'affiche, suivez les étapes de votre marque.

#### Xiaomi / Redmi : HyperOS

1. Si le message « L'installation d'applications de sources inconnues est bloquée » apparaît, touchez « Paramètres » et activez l'autorisation.
2. Ou manuellement : Paramètres → Applications → Autorisations spéciales (ou « Accès spécial aux applications ») → Installer des applications inconnues → votre navigateur → activer.
3. Si une vérification de sécurité s'affiche, attendez quelques secondes puis touchez « Continuer l'installation ».

[Capture à insérer : interrupteur « Installer des applications inconnues » sur HyperOS — à photographier sur un vrai téléphone]

#### Xiaomi / Redmi : MIUI (MIUI 12 à 14)

1. Paramètres → Applications → Gérer les applications → « ⋮ » ou « Autorisations » → Installer des applications inconnues → votre navigateur → « Autoriser cette source ».
2. MIUI analyse le fichier avant l'installation ; cela peut prendre quelques secondes. Touchez ensuite « Continuer l'installation ».

[Capture à insérer : écran d'analyse MIUI et bouton « Continuer l'installation » — à photographier sur un vrai téléphone]

#### Samsung : One UI

1. Paramètres → Applications → « ⋮ » en haut à droite → Accès spécial → Installer applis inconnues → votre navigateur (Chrome, Samsung Internet) ou « Mes fichiers » → « Autoriser depuis cette source ».
2. Sur One UI 6 et plus, si le **« Bloqueur automatique »** (Paramètres → Sécurité et confidentialité → Bloqueur automatique) est activé, il bloque toute installation de ce type.
   Désactivez-le le temps d'installer l'application, puis vous pouvez le réactiver.

[Capture à insérer : « Installer applis inconnues » et « Bloqueur automatique » sur Samsung — à photographier sur un vrai téléphone]

#### Huawei : EMUI et HarmonyOS 2 / 3 / 4

1. Paramètres → Sécurité → Plus de paramètres → Installer des applications de sources externes → votre navigateur ou « Fichiers » → activer.
2. Si le **« Mode pur »** (Paramètres → Système et mises à jour → Mode pur) est activé, il affichera un avertissement : touchez « Installer quand même »,
   ou quittez temporairement le mode pur et réactivez-le après l'installation.
3. **HarmonyOS NEXT (HarmonyOS 5) : installation impossible**, voir l'étape 1.

[Capture à insérer : « Sources externes » et avertissement du « Mode pur » sur Huawei — à photographier sur un vrai téléphone]

### 4. Que faire en cas d'avertissement de sécurité

L'application n'est pas sur un magasin d'applications : le téléphone signale donc une « source inconnue ». C'est normal.

- **Google Play Protect** affiche « Application dangereuse bloquée » ou « Application inconnue » : touchez « Plus de détails » → « Installer quand même ».
  S'il propose d'« envoyer l'application pour analyse », vous pouvez refuser.
- **Contrôle de sécurité Xiaomi / Huawei** : lisez le message, puis touchez « Installer quand même » ou « Continuer l'installation ».
- N'installez **que le fichier téléchargé depuis le QR code du chercheur**, jamais un fichier transféré par quelqu'un d'autre.
- Message « Fichier endommagé » ou « Erreur d'analyse du package » : téléchargez à nouveau. Si le problème continue, envoyez au chercheur le modèle du téléphone et la version d'Android.

[Capture à insérer : Google Play Protect « Installer quand même » — à photographier sur un vrai téléphone]

### 5. Première ouverture

- La première fois que vous touchez le bouton micro (« Démarrer »), l'application explique pourquoi elle a besoin du micro, puis le téléphone vous demande l'autorisation : choisissez « Autoriser » ou « Uniquement si l'application est en cours d'utilisation ».
- Si vous avez refusé par erreur : l'application affiche un bouton « Ouvrir les réglages » → Autorisations → Micro → Autoriser.

### 6. Mettre à jour

- Quand une nouvelle version existe, un message apparaît en haut de l'écran d'exercice. Touchez « Télécharger dans le navigateur », puis installez comme la première fois.
- **Installez par-dessus l'ancienne version, sans la désinstaller.** Désinstaller effacerait les exercices pas encore envoyés.
- Message « Veuillez mettre à jour l'application » : cette version n'est plus prise en charge, mettez à jour dès que possible ; vous pouvez continuer à vous entraîner en attendant.
- Message « Application non installée » ou « conflit de signature » : la version installée ne vient pas du chercheur. Contactez-le, ne désinstallez rien vous-même.

---

## Español

### 1. Comprueba que el teléfono es compatible

- Hace falta **Android 8.0 o más reciente** (Ajustes → Información del teléfono).
- **Huawei con HarmonyOS NEXT (HarmonyOS 5; en «Información del teléfono» aparece «HarmonyOS 5.x»): no se puede instalar.**
  Esta versión ya no acepta archivos de instalación de Android. Ponte en contacto con el investigador. HarmonyOS 2, 3 y 4 sí funcionan.
- El archivo pesa unos 2 MB; puedes descargarlo con wifi o con datos móviles.

### 2. Escanea el código QR y descarga

1. Escanea el código QR que te dio el investigador con la **cámara** o el **navegador** del teléfono
   (si lo abres dentro de WhatsApp o WeChat, elige «Abrir en el navegador»: esas apps no permiten instalar el archivo).
2. En la página que se abre, toca «Descargar». El archivo se llama `pinyintone-versión.apk`.
3. Si el navegador avisa «Este tipo de archivo puede dañar tu dispositivo», elige «Descargar de todos modos».
4. Cuando termine la descarga, toca la notificación o abre el archivo desde la lista de descargas del navegador.

[Captura pendiente: página de descarga y aviso «Descargar de todos modos» — hacerla en un teléfono real]

### 3. Permite «Instalar aplicaciones desconocidas»

Desde Android 8, este permiso se da **app por app**: se concede a la app que abre el archivo (el navegador o el gestor de archivos).
La mayoría de los teléfonos muestran un aviso la primera vez: toca «Ajustes», activa «Permitir de esta fuente» y vuelve atrás para seguir instalando.
Si no aparece ningún aviso, sigue los pasos de tu marca.

#### Xiaomi / Redmi: HyperOS

1. Si aparece «La instalación de apps de fuentes desconocidas está bloqueada», toca «Ajustes» y activa el permiso.
2. O a mano: Ajustes → Aplicaciones → Permisos especiales → Instalar aplicaciones desconocidas → tu navegador → activar.
3. Si aparece una comprobación de seguridad, espera unos segundos y toca «Continuar con la instalación».

[Captura pendiente: interruptor «Instalar aplicaciones desconocidas» en HyperOS — hacerla en un teléfono real]

#### Xiaomi / Redmi: MIUI (MIUI 12 a 14)

1. Ajustes → Aplicaciones → Administrar aplicaciones → «⋮» o «Permisos» → Instalar aplicaciones desconocidas → tu navegador → «Permitir de esta fuente».
2. MIUI analiza el archivo antes de instalarlo; puede tardar unos segundos. Después toca «Continuar con la instalación».

[Captura pendiente: pantalla de análisis de MIUI y botón «Continuar con la instalación» — hacerla en un teléfono real]

#### Samsung: One UI

1. Ajustes → Aplicaciones → «⋮» arriba a la derecha → Acceso especial → Instalar aplicaciones desconocidas → tu navegador (Chrome, Samsung Internet) o «Mis archivos» → «Permitir desde esta fuente».
2. En One UI 6 o posterior, si está activado el **«Bloqueador automático»** (Ajustes → Seguridad y privacidad → Bloqueador automático), bloquea este tipo de instalación.
   Desactívalo mientras instalas la app; luego puedes volver a activarlo.

[Captura pendiente: «Instalar aplicaciones desconocidas» y «Bloqueador automático» en Samsung — hacerla en un teléfono real]

#### Huawei: EMUI y HarmonyOS 2 / 3 / 4

1. Ajustes → Seguridad → Más ajustes → Instalar aplicaciones de fuentes externas → tu navegador o «Archivos» → activar.
2. Si está activado el **«Modo puro»** (Ajustes → Sistema y actualizaciones → Modo puro), mostrará un aviso: toca «Instalar de todos modos»,
   o sal del modo puro un momento y vuelve a activarlo después de instalar.
3. **HarmonyOS NEXT (HarmonyOS 5): no se puede instalar**, ver el paso 1.

[Captura pendiente: «Fuentes externas» y aviso del «Modo puro» en Huawei — hacerla en un teléfono real]

### 4. Qué hacer si aparece un aviso de seguridad

La app no está en ninguna tienda de aplicaciones, por eso el teléfono avisa de que el «origen es desconocido». Es normal.

- Si **Google Play Protect** muestra «App no segura bloqueada» o «App desconocida»: toca «Más detalles» → «Instalar de todos modos».
  Si te pregunta si quieres «enviar la app para analizarla», puedes decir que no.
- **Comprobación de seguridad de Xiaomi / Huawei**: lee el mensaje y toca «Instalar de todos modos» o «Continuar con la instalación».
- Instala **solo el archivo descargado desde el código QR del investigador**; nunca uno que te haya pasado otra persona.
- Si aparece «Archivo dañado» o «Error al analizar el paquete»: vuelve a descargarlo. Si sigue fallando, envía al investigador el modelo del teléfono y la versión de Android.

[Captura pendiente: Google Play Protect «Instalar de todos modos» — hacerla en un teléfono real]

### 5. La primera vez que abres la app

- La primera vez que tocas el botón del micrófono («Grabar»), la app explica para qué necesita el micrófono y luego el teléfono te pide permiso: elige «Permitir» o «Mientras se usa la app».
- Si lo rechazaste por error: la app muestra el botón «Abrir Ajustes» → Permisos → Micrófono → Permitir.

### 6. Actualizar

- Cuando haya una versión nueva, aparecerá un aviso arriba en la pantalla de práctica. Toca «Descargar en el navegador» e instálala igual que la primera vez.
- **Instala encima de la versión anterior, sin desinstalarla.** Desinstalar borraría las prácticas que aún no se han enviado.
- Aviso «Actualiza la app»: esta versión ya no tiene soporte; actualiza cuanto antes. Mientras tanto puedes seguir practicando.
- Aviso «App no instalada» o «conflicto de firma»: la versión instalada no viene del investigador. Ponte en contacto con él y no desinstales nada por tu cuenta.

---

<div dir="rtl" lang="ar">

## العربية

### 1. تأكد من أن هاتفك متوافق

- يلزم **أندرويد 8.0 أو أحدث** (الإعدادات ← حول الهاتف).
- **هواتف هواوي التي تعمل بنظام HarmonyOS NEXT (الإصدار 5، يظهر «HarmonyOS 5.x» في «حول الهاتف»): لا يمكن التثبيت.**
  هذا الإصدار لم يعد يقبل ملفات تثبيت أندرويد. تواصل مع الباحث. أما HarmonyOS 2 و3 و4 فتعمل.
- حجم الملف حوالي 2 ميغابايت، يمكن تنزيله عبر الواي فاي أو بيانات الهاتف.

### 2. امسح رمز QR ونزّل الملف

1. امسح رمز QR الذي أعطاك إياه الباحث باستخدام **الكاميرا** أو **المتصفح**
   (إذا فتحته داخل واتساب أو وي تشات، اختر «فتح في المتصفح»، لأن هذه التطبيقات لا تسمح بتثبيت الملف).
2. في الصفحة التي تُفتح، اضغط «تنزيل». اسم الملف `pinyintone-version.apk`.
3. إذا ظهرت رسالة «قد يضر هذا النوع من الملفات بجهازك»، اختر «التنزيل على أي حال».
4. بعد انتهاء التنزيل، اضغط على الإشعار، أو افتح الملف من قائمة التنزيلات في المتصفح.

[مكان صورة: صفحة التنزيل ورسالة «التنزيل على أي حال» — تُلتقط على هاتف حقيقي]

### 3. اسمح بـ«تثبيت التطبيقات غير المعروفة»

منذ أندرويد 8، يُمنح هذا الإذن **لكل تطبيق على حدة**: تمنحه للتطبيق الذي يفتح الملف (المتصفح أو مدير الملفات).
تعرض معظم الهواتف رسالة في المرة الأولى: اضغط «الإعدادات»، فعّل «السماح من هذا المصدر»، ثم ارجع لإكمال التثبيت.
إذا لم تظهر الرسالة، اتبع خطوات العلامة التجارية لهاتفك.

#### شاومي / ريدمي: HyperOS

1. إذا ظهرت رسالة «تثبيت التطبيقات من مصادر غير معروفة محظور»، اضغط «الإعدادات» وفعّل الإذن.
2. أو يدويًا: الإعدادات ← التطبيقات ← أذونات خاصة ← تثبيت التطبيقات غير المعروفة ← اختر متصفحك ← فعّل.
3. إذا ظهر فحص أمني، انتظر بضع ثوانٍ ثم اضغط «متابعة التثبيت».

[مكان صورة: مفتاح «تثبيت التطبيقات غير المعروفة» في HyperOS — تُلتقط على هاتف حقيقي]

#### شاومي / ريدمي: MIUI (من 12 إلى 14)

1. الإعدادات ← التطبيقات ← إدارة التطبيقات ← «⋮» أو «الأذونات» ← تثبيت التطبيقات غير المعروفة ← متصفحك ← «السماح من هذا المصدر».
2. يفحص MIUI الملف قبل التثبيت، وقد يستغرق ذلك بضع ثوانٍ. ثم اضغط «متابعة التثبيت».

[مكان صورة: شاشة الفحص في MIUI وزر «متابعة التثبيت» — تُلتقط على هاتف حقيقي]

#### سامسونج: One UI

1. الإعدادات ← التطبيقات ← «⋮» في الأعلى ← وصول خاص ← تثبيت التطبيقات غير المعروفة ← متصفحك (Chrome أو Samsung Internet) أو «ملفاتي» ← «السماح من هذا المصدر».
2. في One UI 6 وما بعده، إذا كانت ميزة **«الحظر التلقائي»** مفعّلة (الإعدادات ← الأمان والخصوصية ← الحظر التلقائي)، فهي تمنع هذا النوع من التثبيت.
   أوقفها أثناء التثبيت، ويمكنك تفعيلها مرة أخرى بعد ذلك.

[مكان صورة: «تثبيت التطبيقات غير المعروفة» و«الحظر التلقائي» في سامسونج — تُلتقط على هاتف حقيقي]

#### هواوي: EMUI وHarmonyOS 2 / 3 / 4

1. الإعدادات ← الأمان ← المزيد من الإعدادات ← تثبيت التطبيقات من مصادر خارجية ← متصفحك أو «الملفات» ← فعّل.
2. إذا كان **«الوضع النقي»** مفعّلًا (الإعدادات ← النظام والتحديثات ← الوضع النقي)، فسيعرض تحذيرًا: اضغط «التثبيت على أي حال»،
   أو أوقفه مؤقتًا ثم فعّله بعد التثبيت.
3. **HarmonyOS NEXT (الإصدار 5): لا يمكن التثبيت**، انظر الخطوة 1.

[مكان صورة: «مصادر خارجية» وتحذير «الوضع النقي» في هواوي — تُلتقط على هاتف حقيقي]

### 4. ماذا تفعل عند ظهور تحذير أمني

التطبيق غير موجود في متجر التطبيقات، لذلك ينبّهك الهاتف إلى أن «المصدر غير معروف». هذا أمر عادي.

- إذا عرضت **Google Play Protect** رسالة «تم حظر تطبيق غير آمن» أو «تطبيق غير معروف»: اضغط «مزيد من التفاصيل» ← «التثبيت على أي حال».
  إذا طلبت «إرسال التطبيق للفحص»، يمكنك الرفض.
- **الفحص الأمني في شاومي / هواوي**: اقرأ الرسالة ثم اضغط «التثبيت على أي حال» أو «متابعة التثبيت».
- لا تثبّت **إلا الملف الذي نزّلته من رمز QR الخاص بالباحث**، ولا تثبّت أبدًا ملفًا أرسله لك شخص آخر.
- إذا ظهرت رسالة «الملف تالف» أو «خطأ في تحليل الحزمة»: نزّل الملف مرة أخرى. إذا استمرت المشكلة، أرسل إلى الباحث طراز الهاتف وإصدار أندرويد.

[مكان صورة: Google Play Protect «التثبيت على أي حال» — تُلتقط على هاتف حقيقي]

### 5. أول مرة تفتح فيها التطبيق

- عند أول ضغطة على «تسجيل»، يشرح التطبيق سبب حاجته إلى الميكروفون، ثم يطلب منك الهاتف الإذن: اختر «السماح» أو «أثناء استخدام التطبيق فقط».
- إذا رفضت عن طريق الخطأ: يعرض التطبيق زر «فتح الإعدادات» ← الأذونات ← الميكروفون ← السماح.

### 6. التحديث

- عند توفر إصدار جديد، تظهر رسالة في أعلى شاشة التمرين. اضغط «التنزيل عبر المتصفح»، ثم ثبّت الملف كما فعلت في المرة الأولى.
- **ثبّت الإصدار الجديد فوق القديم دون إلغاء تثبيته.** إلغاء التثبيت يحذف التمارين التي لم تُرسل بعد.
- رسالة «يرجى تحديث التطبيق»: هذا الإصدار لم يعد مدعومًا، حدّثه في أقرب وقت؛ يمكنك متابعة التمرين حتى ذلك الحين.
- رسالة «لم يتم تثبيت التطبيق» أو «تعارض في التوقيع»: الإصدار المثبّت ليس من الباحث. تواصل معه، ولا تلغِ التثبيت بنفسك.

</div>
