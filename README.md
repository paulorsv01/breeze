<p align="center">
  <img src="Resources/IconPreview.png" width="128" alt="Ícone do Breeze">
</p>

# Breeze

Controle de ventoinhas para macOS, direto na barra de menus. Interface em português, inglês e espanhol, com presets ajustáveis e retorno ao controle automático do macOS ao sair.

## O que ele faz

- Mostra rotação das ventoinhas e a maior temperatura disponível nos sensores de CPU/GPU.
- Oferece três presets: **Automático**, **Performance** e **Performance+**.
- Permite ajustar rotação inicial, temperatura de início da curva e temperatura de rotação máxima nos dois presets personalizados.
- Salva os ajustes e o último preset escolhido.
- Tem uma janela de ajustes com inicialização junto ao login e desativação do serviço.
- Usa a cor turquesa de forma consistente, com aparência clara e escura.

O app fica somente na barra de menus, sem ícone permanente no Dock. O idioma segue a preferência do macOS; você também pode escolher um idioma por aplicativo em **Ajustes do Sistema → Geral → Idioma e Região → Aplicativos**.

## Requisitos

- macOS 14 ou mais recente.
- Mac com Apple Silicon, ventoinhas e chaves SMC compatíveis. Macs sem ventoinhas não são suportados.
- Autorização do serviço em **Ajustes do Sistema → Geral → Itens de Início e Extensões** para alterar a rotação.

A compatibilidade depende do hardware. Este projeto não usa uma API pública da Apple para controlar ventoinhas. Os testes automatizados usam hardware simulado e não garantem funcionamento em todos os modelos.

## Instalação

Baixe o ZIP na página de [releases](https://github.com/paulorsv01/breeze/releases), extraia e mova **Breeze.app** para **Aplicativos** antes de ativar o serviço. Evite mover o app enquanto o serviço estiver registrado.

O binário deste primeiro release usa um certificado **Apple Development pessoal**, e **não é notarizado**. O macOS pode impedir a abertura ou exigir aprovação manual. Ele não oferece a mesma experiência de instalação de um app distribuído com Developer ID e notarização. Compilar e assinar localmente é outra opção.

O identificador do app é `com.breeze.fancontrol`; o serviço usa `com.breeze.fancontrol.Helper`.

Se você já usa uma versão local com outro identificador, desative o controle e encerre essa versão antes de abrir esta. As preferências da versão antiga não são migradas.

## Presets

| Preset | Padrão de fábrica |
| --- | --- |
| Automático | Delega o controle ao macOS |
| Performance | 60% da rotação máxima até 40 °C; cresce linearmente até 100% em 75 °C |
| Performance+ | 100% da rotação máxima |

Nos Ajustes, os botões −/+ alteram cada parâmetro. A rotação inicial pode variar de 30% a 100%; o início da curva, de 30 a 65 °C; e a rotação máxima, de 50 a 85 °C. Há sempre pelo menos 5 °C entre início e fim da curva. Os limites físicos de cada ventoinha prevalecem sobre o percentual configurado.

A edição de um preset ativo tenta aplicar a nova configuração imediatamente. **Restaurar padrões** recupera os valores de fábrica daquele preset. Uma temperatura indisponível ou inválida leva à rotação máxima enquanto um preset personalizado está ativo.

## Proteções do controle

O serviço privilegiado valida a configuração e a assinatura do aplicativo antes de aceitar comandos. App e serviço precisam estar assinados por uma identidade Apple do mesmo time. A instância que iniciou o controle mantém uma concessão de oito segundos, renovada pelo app.

Quando o app sai, desconecta ou deixa de renovar essa concessão, o serviço tenta devolver o controle ao macOS. Falhas de restauração são tentadas novamente. Esses mecanismos dependem de o serviço e o hardware conseguirem responder; não substituem o gerenciamento térmico do sistema.

Para remover o app, use **Ajustes → Desativar controle**, encerre o Breeze e só então remova o aplicativo.

## Compilar

Instale o Xcode com suporte a Swift 6 e o [XcodeGen](https://github.com/yonaskolb/XcodeGen). O projeto Xcode é gerado a partir de `project.yml`; não há dependências externas de runtime.

Escolha explicitamente seu certificado:

```sh
security find-identity -v -p codesigning
SIGNING_IDENTITY='<fingerprint do seu certificado>' CONFIGURATION=Release \
  bash script/build_and_run.sh --build-only
```

O script não escolhe certificados automaticamente. Ele compila o app e o helper, assina ambos e verifica suas assinaturas. O pacote fica em `build/DerivedData/Build/Products/Release/Breeze.app`.

Para compilar e abrir em modo Debug, use o mesmo comando sem `--build-only`. O script também oferece `--debug`, `--logs` e `--telemetry`.

Testes do núcleo:

```sh
swift test --package-path Core
```

Em ambientes que usam `bqueue`, execute builds e testes por essa fila.

Para gerar novamente o ICNS a partir do PNG versionado:

```sh
bash script/generate_icons.sh
```

## Estrutura

- `App`: interface SwiftUI, estado, preferências e cliente XPC.
- `Core`: acesso ao SMC, modelos, curvas e controlador com testes.
- `Helper`: serviço privilegiado e ciclo de controle.
- `Shared`: protocolo XPC e validação de assinatura.
- `Resources`: traduções, ícones e manifesto do serviço.

As traduções ficam em `Resources/Localizable.xcstrings`. Mensagens técnicas de diagnóstico podem aparecer em inglês. O prompt usado no ícone está em `Resources/IconPrompt.md`.

## Licença

[MIT](LICENSE), © 2026 Paulo Vieira.
