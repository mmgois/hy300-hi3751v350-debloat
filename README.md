# HY300 projector (HiSilicon Hi3751V350): ADB, debloat and launcher swap

> **English summary.** Some cheap "HY300" mini projectors are not the Allwinner H713 or Rockchip
> RK3326 boards that most guides cover: this one is a **HiSilicon Hi3751V350** (`bigfish`),
> Android 12 `userdebug`. Developer options are blocked and USB is host-only, but **network ADB
> is already open on port 13111 with no authentication**. This repo documents how it was found,
> how the Home button was pointed at Projectivy (`persist.sys.home.selectpkg` + `com.jm.jmlauncher`),
> what was removed, and a **fake YouTube app** shipped from the factory that silently installs
> other apps. The full guide below is in Brazilian Portuguese.

Guia do que foi feito num mini projetor vendido como "HY300", para deixá-lo mais leve, trocar a
tela inicial e remover apps suspeitos de fábrica. Tudo foi feito por ADB, sem root e sem abrir o
aparelho. Testado em um único aparelho, em novembro de 2026.

## Identificação

Confira antes de seguir: os guias de "HY300" na internet tratam de placas diferentes com o mesmo
nome (Allwinner H713, Rockchip RK3326, Amlogic T950S) e não se aplicam a esta.

| Propriedade | Valor |
|---|---|
| `ro.product.device` | `Hi3751V350` |
| `ro.board.platform` | `bigfish` |
| Android | 12, build `userdebug` |
| `ro.build.fingerprint` | `google/redfin/...` (finge ser um Pixel 5) |
| RAM | ~2 GB |
| Build visível no menu | `JM_P1-2026...` |
| Launcher de fábrica | `com.tcl.movieark.launcher`, `com.htc.htclauncherhighenglishd08` |

Sem ADB, um sinal desta variante: o easter egg da versão do Android mostra um relógio (Android 12)
e **não** existem pacotes `com.rockchip.*` nem `com.hotack.*` (verificável pelo Activity Launcher).

## O que não funciona nesta placa

- **Opções do desenvolvedor**: tocar 7× em "Build do SO do Android TV" ou no nome do modelo não
  faz nada. Abrir `DevelopmentActivity` pelo Activity Launcher mostra "as opções do desenvolvedor
  não estão disponíveis para este usuário".
- **ADB por USB**: a porta USB-A do projetor é só *host*. Lê pendrive **em FAT32** (exFAT não
  aparece), mas não fala ADB com um PC. Um cabo USB A-A liga os 5 V dos dois lados e chega a
  alimentar a placa pelo PC: **não deixe o cabo A-A ligado com o projetor na tomada**.
- **Recovery** pelos botões (segurar power ao ligar, power + volume, etc.): nada funcionou.
- O menu "Depurar USB – Ativo" do fabricante não abre a porta 5555.

## 1. Encontrar o ADB (porta 13111)

O ADB pela rede **já vem ligado de fábrica**, numa porta fora do padrão e sem autenticação:

```
persist.adb.tcp.port=13111
service.adb.tcp.port=13111
ro.adb.secure=        (vazio: nenhuma confirmação na tela)
```

Para encontrar a porta em outro aparelho, use [`scan-adb.sh`](scan-adb.sh): ele varre as portas
TCP e testa cada uma com `adb` (serviços que não são ADB aceitam a conexão, mas ficam `offline`).

```bash
./scan-adb.sh 192.168.0.50            # todas as portas (leva alguns minutos)
./scan-adb.sh 192.168.0.50 13000 14000
adb connect 192.168.0.50:13111
```

As demais portas abertas (11022, 11101–11104, 4321, 38400 e algumas altas aleatórias) pertencem a
serviços do sistema (uid `system`/`root`: Miracast e serviços de TV da HiSilicon), não a apps de
terceiros.

Exemplos abaixo usam `adb -s <ip>:13111 shell ...`, abreviado como `adb shell`.

## 2. Animações desligadas

O maior ganho percebido na navegação:

```bash
adb shell settings put global window_animation_scale 0
adb shell settings put global transition_animation_scale 0
adb shell settings put global animator_duration_scale 0
```

## 3. Trocar a tela inicial pelo Projectivy

Instale o **Projectivy Launcher** pela Play Store. Só definir o launcher padrão **não basta**:
o firmware foi modificado para que o botão Home envie a categoria própria
`android.intent.category.HOME.JM`, atendida apenas pelo `com.jm.jmlauncher`. Ele é um
"despachante" que abre o pacote definido em `persist.sys.home.selectpkg` (de fábrica, o launcher
HTC). Como o build é `userdebug`, `setprop` funciona pelo `adb shell`:

```bash
adb shell cmd package set-home-activity --user 0 com.spocky.projengmenu/.ui.home.MainActivity
adb shell setprop persist.sys.home.selectpkg com.spocky.projengmenu
adb shell pm disable-user --user 0 com.tcl.movieark.launcher
adb shell pm disable-user --user 0 com.htc.htclauncherhighenglishd08
```

> ⚠️ **Nunca desative `com.jm.jmlauncher`.** Sem ele o Home cai no `FallbackHome` ("User unlocked
> but no home") e a tela fica preta. Se acontecer: `adb shell pm enable com.jm.jmlauncher`.

A configuração sobreviveu a reinícios.

## 4. Remover e desativar apps

**Desinstalados** (vinham de fábrica em `/data/app`, então a remoção é limpa; um reset de fábrica
os traz de volta):

| Pacote | O que é |
|---|---|
| `com.google.android.youtube.tv` (falso) | ver [seção 5](#5-youtube-falso-de-fábrica) |
| `com.tv.flarehub` | "Flarehub", 100 MB, assinado por `CN=metax_os` |
| `com.unitvnet.tvod` | UniTV, IPTV pirata |
| `com.eusfu.appstore` | loja de apps paralela |
| `com.tv9c.upgrade` | atualizador do fabricante (conectava a um IP da Alibaba Cloud) |
| `com.tcl.browser` | navegador TCL |
| `com.mobisystems.office` | Office pré-instalado |
| `com.bozee.usbdisplay` | espelhamento de tela, rodando o tempo todo (~27 MB de RAM) |
| `com.netflix.mediaclient`, `com.disney.disneyplus`, `com.amazon.amazonvideo.livingroom` | não usados |

```bash
adb uninstall <pacote>
```

**Desativados** (apps de sistema; reversível com `pm enable`):

| Pacote | Motivo |
|---|---|
| `com.tcl.movieark.launcher`, `com.htc.htclauncherhighenglishd08` | launchers substituídos |
| `com.define.shellservice` | serviço exportado, roda como `system` e aceita a ação `com.define.shellservice.shellcommand` (executa comandos). Nada do projetor deixou de funcionar sem ele: trapézio, foco, troca de fonte e imagem testados |

```bash
adb shell pm disable-user --user 0 com.define.shellservice
```

**Acessibilidade pré-autorizada para um pacote inexistente.** A configuração de fábrica autoriza
`com.android.nfx/com.android.nfx.NfxAccessibilityService`, que não está instalado. Se um app com
esse nome fosse instalado (por um atualizador, por exemplo), ganharia na hora permissão para ler a
tela e simular toques. Mantenha só o serviço da HiSilicon:

```bash
adb shell settings put secure enabled_accessibility_services \
  com.hisilicon.rmservice/com.hisilicon.rmservice.HiRMService
```

**Não mexa** em: `com.jm.jmlauncher`, `com.htc.htcsettings` (configurações), `com.softwinner.tcorrection`
(trapézio), `com.hisilicon.*` (serviços de TV, entrada HDMI, controle remoto), `com.vendor.vnaudiomanager`
(áudio).

## 5. YouTube falso de fábrica

O app "YouTube" pré-instalado usa o nome de pacote do oficial (`com.google.android.youtube.tv`,
versão `2026.06.3018`), mas:

- tem **2,3 MB** (o oficial tem ~50 MB) e código de outro desenvolvedor (`com.wuliang.*`);
- só abre o Flarehub apontando para o site: `flarehubtv://{"type":6,"url":"https://www.youtube.com/tv"}`;
- contém código de **instalação silenciosa** de apps (`com.google.android.youtube.tv.ACTION_SILENCE_INSTALL`,
  `PackageInstaller`, `initSilenceInstalledReceiver`) — ao desinstalar o Flarehub, ele pedia para
  reinstalá-lo.

| Arquivo | SHA-256 |
|---|---|
| YouTube falso (`base.apk`) | `7cdcbeff7866db75333043ddae3158c4d26a00720b0828c92f755e5dca2ea336` |
| Flarehub (`base.apk`) | `adc537151adc19d5301dc64c6f9a09de1279e5284f1654cc44cc304e9ccc58a9` |

Para conferir no seu aparelho:

```bash
adb shell pm path com.google.android.youtube.tv
adb shell dumpsys package com.google.android.youtube.tv | grep -E 'versionName|installerPackageName'
```

Se o APK tiver poucos MB e não houver `installerPackageName=com.android.vending`, é o falso.
Desinstale-o e instale o oficial pela Play Store ("YouTube for Android TV", Google LLC).

Para procurar outros apps falsos, compare as chaves de assinatura: um app com nome do Google
assinado com chave diferente dos outros apps do Google é suspeito. Neste aparelho, Play Services,
Play Store, GSF, Chromecast integrado e Chrome tinham chaves coerentes; só o YouTube destoava.

## 6. Apps instalados no lugar

- **Projectivy Launcher**, **YouTube for Android TV** e **Symfonium** (cliente Subsonic/Navidrome;
  `app.symfonik.music.player`) pela Play Store. Compras feitas no celular valem no projetor se a
  conta Google for a mesma.
- **Jellyfin for Android TV** pelo [GitHub oficial](https://github.com/jellyfin/jellyfin-androidtv/releases)
  com `adb install -r jellyfin-androidtv-<versão>-release.apk` (sem atualização automática).

## Resultado e considerações

- Saíram da memória uns 40–60 MB fixos (launcher TCL 53 MB → Projectivy ~41 MB; `usbdisplay` 27 MB;
  processos que acordavam em segundo plano). O armazenamento livre subiu de 2,6 para 2,9 GB, já
  contando os apps novos.
- **O hardware continua sendo o gargalo**: com Jellyfin (~95 MB) e Symfonium (~70 MB) abertos, o
  aparelho usa ~350 MB de swap. Use um app pesado por vez. Para desempenho de verdade, um stick HDMI.
- O **Chrome** de fábrica é legítimo, mas a Play Store o considera "não compatível" e ele fica preso
  na versão 133 (início de 2025), sem correções de segurança. Use só em sites conhecidos.
- **O ADB fica aberto, sem senha, para toda a rede local** e não há como desligá-lo de forma
  persistente (num Redmi Projector Lite com o mesmo chip, `setprop` volta ao valor original após
  reiniciar). Deixe o projetor numa **rede de convidados**, isolada dos outros aparelhos.
- O chip é diferente, mas os apps de fábrica (YouTube falso, loja paralela, IPTV pirata) seguem o
  padrão das denúncias de malware em projetores baratos (BADBOX 2.0, proxy residencial). Não foi
  encontrado tráfego de proxy neste aparelho, mas o Flarehub não foi analisado por dentro.

## Como desfazer

```bash
adb shell pm enable <pacote>                                   # reativar
adb shell setprop persist.sys.home.selectpkg com.htc.htclauncherhighenglishd08
adb shell settings put global window_animation_scale 1         # idem para as outras duas
```

Apps desinstalados de `/data` só voltam com reset de fábrica.

## Referências

- [Free My TV PR #230](https://github.com/simbasjungles/free-my-tv/pull/230): o mesmo mecanismo
  `HOME.JM` / `persist.sys.home.selectpkg` numa placa Amlogic.
- [hy300t-android-guia](https://github.com/mariorodriguesoficial/hy300t-android-guia): HY300-T
  (Amlogic T950S); avisa para nunca desativar o `com.jm.jmlauncher`.
- [cleanyourtv #1178](https://github.com/Gathin23/cleanyourtv/issues/1178): Redmi Projector Lite,
  mesmo chip Hi3751V350, ADB aberto sem autenticação e impossível de desligar.
- [BruBread/Hy300-Root](https://github.com/BruBread/Hy300-Root) (RK3326) e
  [HY300_PRO.md](https://gist.github.com/probonopd/3ad6b7777caea1503f00d5fe7710ad06) (Allwinner H713):
  outras placas vendidas como HY300.
- [FBI / BADBOX 2.0](https://www.bleepingcomputer.com/news/security/fbi-badbox-20-android-malware-infects-millions-of-consumer-devices/).

## Aviso

Feito num aparelho próprio. Use por sua conta e risco: nada aqui mexe no bootloader ou nas
partições do sistema, mas desativar o pacote errado pode deixar a tela inicial preta até ser
revertido pelo ADB.

## Licença

MIT. Veja [LICENSE](LICENSE).
