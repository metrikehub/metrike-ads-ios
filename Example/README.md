# Metrike Ads SDK -- Example (iOS)

App de exemplo/integração viva do Metrike Ads SDK para iOS (UIKit). Consome
**exclusivamente a API pública** do módulo `MetrikeAds` (`import MetrikeAds`)
-- nenhum tipo interno é usado em nenhum arquivo aqui. O que você vê nesta
tela é exatamente o que a documentação de integração descreve.

Galeria dos 6 formatos: banner, interstitial, VAST fullscreen, outstream,
instream (IMA-style) e MRAID (servido pela própria zona de banner -- veja a
nota na tela). Um **event log** fica fixo na parte de baixo da tela o tempo
todo, mostrando toda linha de debug do SDK (`MetrikeDebugListener`) e todo
callback de delegate de cada formato -- o log É a demo.

## Configuração (obrigatória antes de carregar qualquer formato)

Os campos **Zone ID** e **VAST token** da tela começam **vazios** e são
persistidos em `UserDefaults` -- preencha-os com uma zona sua antes de tocar
em qualquer botão de formato (os de display usam o Zone ID; os de vídeo --
VAST fullscreen, outstream e instream -- usam o VAST token). Enquanto um
deles estiver vazio, o botão correspondente não chama o SDK e o event log
diz qual campo falta.

Nada vem fixado no código de propósito: o fonte deste app é publicado no
repositório público `metrike-ads-ios`, então uma zona ou token embutido aqui
ficaria permanentemente público no histórico do git. Mesmo contrato do
testapp Android (`TestConfig.zoneId`/`vastToken`, ambos `""` por padrão).
**Use sempre uma zona de teste -- nunca uma zona real de cliente.**

## Build (2 comandos)

Este diretório **não contém um `.xcodeproj`** -- ele é gerado a partir de
`project.yml` pelo [XcodeGen](https://github.com/yonaskolb/XcodeGen), em um
Mac com Xcode instalado:

```sh
brew install xcodegen
xcodegen generate
```

Isso cria `MetrikeExample.xcodeproj` neste diretório (não versionado -- veja
`.gitignore`). Abra-o:

```sh
open MetrikeExample.xcodeproj
```

O projeto gerado já depende do SDK como **Swift Package local**
(`../` -- `sdk/ios/Package.swift`, produto `MetrikeAds`), então qualquer
mudança feita no SDK em `sdk/ios/Sources/MetrikeAds/` é refletida no próximo
build do Example sem nenhum passo extra.

## Rodar no Simulator

Selecione o esquema `MetrikeExample` e qualquer simulador de iPhone
(deployment target: iOS 14.0), `Cmd+R`. Por padrão o app inicializa contra
`https://track.metrike.com.br` (ambiente "Prod" na tela); preencha Zone ID e
VAST token na tela antes de carregar qualquer formato (veja "Configuração"
acima).

## Rodar contra o stack local

Suba `docker-compose.dev.yml` (serviço `ingestion`, porta publicada `8005`)
e, na tela do app, mude o segmented control de ambiente para "Local".
**O SDK só lê esse valor uma vez, no `Metrike.initialize(config:)` chamado
pelo `AppDelegate` -- não há API pública para reapontar um SDK já
inicializado.** A tela avisa isso: feche e reabra o app (Cmd+Shift+H,
Cmd+Q no Simulator; ou simplesmente pare e rode de novo) para o novo
ambiente realmente entrar em vigor -- mesmo comportamento e mesmo motivo do
testapp Android (`TestConfig.activeEnv`/`TestConfig.pendingEnv`).

- **Simulator**: `http://127.0.0.1:8005` funciona direto -- o Simulator
  compartilha a própria stack de rede do Mac.
- **Dispositivo físico** na mesma rede Wi-Fi: `127.0.0.1` é o loopback do
  *aparelho*, não do Mac -- troque `TestConfig.Env.local.baseUrl` (ou digite
  o host manualmente, se você adicionar esse campo) pelo IP de LAN do Mac,
  ex. `http://192.168.0.42:8005`.

## Instalar em um iPhone físico com Apple ID gratuito

Não é necessário ter uma conta paga da Apple Developer Program para instalar
este app em um iPhone próprio para teste:

1. Abra `MetrikeExample.xcodeproj` no Xcode, aba **Signing & Capabilities**
   do target `MetrikeExample`.
2. Em **Team**, escolha seu Apple ID pessoal (adicione-o em
   Xcode → Settings → Accounts, se ainda não estiver lá) -- o Xcode cria um
   certificado de desenvolvimento gratuito automaticamente
   ("Automatically manage signing" já vem marcado em `project.yml`).
3. Conecte o iPhone por cabo (ou Wi-Fi já pareado), selecione-o como
   destino, `Cmd+R`.
4. No iPhone, na primeira execução: **Ajustes → Geral → VPN e Gerenciamento
   de Dispositivo** → confie no seu Apple ID de desenvolvedor.
5. Um app instalado com Apple ID gratuito expira em 7 dias -- basta rodar
   `Cmd+R` de novo do Xcode para renovar.

## Estrutura

```
Example/
├── project.yml              # spec do XcodeGen (gera o .xcodeproj -- não commitado)
├── README.md                 # este arquivo
└── Sources/
    ├── AppDelegate.swift              # Metrike.initialize(config:) + deep links
    ├── TestConfig.swift               # zone/token/env persistidos (UserDefaults)
    ├── EventLogView.swift             # EventLog (singleton) + a view fixa na tela
    ├── MainViewController.swift       # galeria dos formatos + configuração
    ├── InstreamDemoViewController.swift  # AVPlayer + MetrikeAdsLoader
    └── Info.plist                     # gerado por project.yml (launch screen, orientações, esquema de deep link)
```
