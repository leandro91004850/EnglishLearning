# Instalar no iPhone (e renovar a assinatura)

O app vai direto do Mac para o iPhone, sem App Store, assinado com uma conta Apple **gratuita** (o
"time" do Xcode). Essa assinatura — o perfil de desenvolvedor — vale **7 dias**: depois disso o app
para de abrir no iPhone e precisa ser reinstalado (veja [Renovar a assinatura](#renovar-a-assinatura-a-cada-7-dias)).

Todos os comandos são rodados num Mac, na pasta `legendas_yt`.

## Uma vez só: preparar o Mac e o iPhone

1. **Xcode** com a sua conta Apple: Xcode › Settings › Accounts. No projeto (`ios/Runner.xcworkspace`
   › Runner › Signing & Capabilities), o **Team** escolhido e **Automatically manage signing** ligado.
2. Ligue o iPhone no Mac por um **cabo de dados** (há cabos que só carregam) e, no iPhone, toque em
   **Confiar** em "Confiar neste computador?".
3. **Modo de Desenvolvedor** no iPhone: Ajustes › Privacidade e Segurança › Modo de Desenvolvedor
   (o iPhone reinicia).
4. Para instalar depois **pelo Wi-Fi**, sem cabo: Xcode › Window › Devices and Simulators › o iPhone ›
   **Connect via network**. O iPhone precisa estar no mesmo Wi-Fi do Mac.
5. Depois da primeira instalação, o iPhone pede para **confiar no desenvolvedor**: Ajustes › Geral ›
   VPN e Gerenciamento de Dispositivos › App de Desenvolvedor › a sua conta › **Confiar**.

## Instalar (ou atualizar)

Com o iPhone **desbloqueado e com a tela acesa**:

```bash
xcrun devicectl list devices
```

O iPhone tem que aparecer como `available (paired)`. Depois:

```bash
flutter build ios --release
```

```bash
ID=$(xcrun devicectl list devices | grep -i iphone | grep -Eo '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}' | head -1)
```

```bash
xcrun devicectl device install app --device "$ID" build/ios/iphoneos/Runner.app
```

```bash
xcrun devicectl device process launch --device "$ID" com.englishlearning.legendasYt
```

- O `ID` é o identificador do iPhone (o mesmo que `xcrun devicectl list devices` mostra).
- **Não use `flutter install`**: ele desinstala o app antes e apaga os dados dele (o endereço e a chave
  da API, em Servidor). O `devicectl device install` atualiza o app e mantém os dados.
- O último comando só abre o app; com o iPhone bloqueado ele falha (`Locked`), mas o app já está
  instalado: é só abrir pelo ícone.

### Tudo de uma vez

Pelo Wi-Fi a conexão às vezes cai no meio; este bloco tenta instalar até 6 vezes:

```bash
flutter build ios --release && \
ID=$(xcrun devicectl list devices | grep -i iphone | grep -Eo '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}' | head -1) && \
for i in 1 2 3 4 5 6; do
  xcrun devicectl device install app --device "$ID" build/ios/iphoneos/Runner.app && break
  echo "Tentativa $i não deu; tentando de novo…"; sleep 6
done && \
xcrun devicectl device process launch --device "$ID" com.englishlearning.legendasYt
```

## Renovar a assinatura (a cada 7 dias)

Até quando vale a assinatura do último build (na hora local):

```bash
exp=$(security cms -D -i build/ios/iphoneos/Runner.app/embedded.mobileprovision | plutil -extract ExpirationDate raw -o - -) && date -r "$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$exp" +%s)" '+A assinatura vale até %d/%m/%Y às %H:%M'
```

Quando ela vence, o app para de abrir no iPhone, e a instalação falha com:

```
Este app não pode ser instalado porque sua integridade não pode ser verificada.
... (This provisioning profile has expired.)
```

Para renovar:

1. **Compile de novo** (`flutter build ios --release`). Com a assinatura automática, o Xcode vê que o
   perfil venceu e gera um novo, válido por mais 7 dias. Confira com o comando acima: a data tem que
   ter mudado.
2. **Instale** como em [Instalar](#instalar-ou-atualizar) (os dados do app ficam).
3. No iPhone, **confie no desenvolvedor de novo** (o perfil é outro): Ajustes › Geral › VPN e
   Gerenciamento de Dispositivos › App de Desenvolvedor › a sua conta › **Confiar**. Sem isso, abrir o
   app falha com `Security ... has not been explicitly trusted by the user`.

Com uma conta paga do Apple Developer Program, o perfil vale um ano em vez de 7 dias.

## Quando algo dá errado

| Mensagem | O que fazer |
| --- | --- |
| `unavailable` em `xcrun devicectl list devices`, ou `CoreDeviceService was unable to locate a device` | O Mac não acha o iPhone: desbloqueie o iPhone (tela acesa) e confira o mesmo Wi-Fi do Mac, ou ligue pelo cabo. |
| `The tunnel connection failed`, `The peer is no longer reachable` ou `Operation timed out` | A conexão sem fio caiu no meio: deixe a tela acesa (Bloqueio Automático em "Nunca" por um momento, em Ajustes › Tela e Brilho) e tente de novo — o bloco [Tudo de uma vez](#tudo-de-uma-vez) já tenta várias vezes. |
| `Failed to install the app` (erro 3002) com `This provisioning profile has expired` | A assinatura venceu: [renove](#renovar-a-assinatura-a-cada-7-dias). |
| Abrir o app: `Locked` | O iPhone está bloqueado: desbloqueie e abra pelo ícone. |
| Abrir o app: `Security ... has not been explicitly trusted by the user` | Confie no desenvolvedor: Ajustes › Geral › VPN e Gerenciamento de Dispositivos. |
| O cabo está ligado, mas o Mac não vê o iPhone | `ioreg -p IOUSB -w0 \| grep -i iphone` não mostra nada: o cabo só carrega, ou não está direto no Mac. Troque o cabo ou a porta. |

## O app no iPhone e a API

O app pega tudo da API (o servidor do Legendas YT, projeto `api_english`), que roda no Mac. No iPhone,
"localhost" é o próprio iPhone, então em **Servidor** vai o endereço do Mac na rede:

```bash
ipconfig getifaddr en0
```

O endereço fica `http://<esse IP>:8000`, com a chave da API (`API_TOKEN`). Na primeira conexão o iPhone
pede acesso à **Rede Local**: toque em Permitir. A API precisa estar ligada no Mac (veja o README do
`api_english`), com o iPhone no mesmo Wi-Fi; se o IP do Mac mudar, atualize em Servidor.
