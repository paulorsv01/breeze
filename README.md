<p align="center">
  <img src="Resources/IconPreview.png" width="128" alt="Ícone do Breeze">
</p>

# Breeze

Controle de ventoinhas para macOS, direto na barra de menus. Interface em português, inglês e espanhol, com presets ajustáveis e retorno ao controle automático do macOS ao sair.

## O que ele faz

- Mostra rotação das ventoinhas e a maior temperatura disponível nos sensores de CPU/GPU.
- Oferece três presets: **Automático**, **Performance** e **Performance+**.
- Permite ajustar rotação inicial, temperaturas da curva e margem de resfriamento nos dois presets personalizados.
- Salva os ajustes e o último preset escolhido.
- Tem ajustes dentro do próprio painel, com prévia da curva, inicialização junto ao login e desativação do serviço.
- Usa a cor turquesa de forma consistente, com aparência clara e escura.

O app fica somente na barra de menus, sem ícone permanente no Dock. O idioma segue a preferência do macOS; você também pode escolher um idioma por aplicativo em **Ajustes do Sistema → Geral → Idioma e Região → Aplicativos**.

## Requisitos

- macOS 14 ou mais recente.
- Mac com Apple Silicon, ventoinhas e chaves SMC compatíveis. Macs sem ventoinhas não são suportados.
- Autorização do serviço em **Ajustes do Sistema → Geral → Itens de Início e Extensões** para alterar a rotação.

A compatibilidade depende do hardware. Este projeto não usa uma API pública da Apple para controlar ventoinhas. Os testes automatizados usam hardware simulado e não garantem funcionamento em todos os modelos.

## Presets

| Preset | Padrão de fábrica |
| --- | --- |
| Automático | Delega o controle ao macOS |
| Performance | 60% da rotação máxima até 40 °C; cresce linearmente até 100% em 75 °C |
| Performance+ | 100% da rotação máxima |

Nos Ajustes, selecione o preset e use os sliders ou botões −/+ para alterar cada parâmetro. O gráfico mostra as curvas de aquecimento e resfriamento. A rotação inicial pode variar de 30% a 100%; o início da curva, de 30 a 65 °C; e a rotação máxima, de 50 a 85 °C. Há sempre pelo menos 5 °C entre início e fim da curva. Os limites físicos de cada ventoinha prevalecem sobre o percentual configurado.

A margem de resfriamento começa em 5 °C e pode variar de 0 a 10 °C. Pequenas quedas de temperatura mantêm a rotação; depois de ultrapassar essa margem, a rotação diminui gradualmente. O aquecimento continua podendo elevar a rotação sem espera adicional. Por exemplo, após atingir 60 °C com margem de 5 °C, a curva mantém o alvo até 55 °C e começa a reduzi-lo abaixo disso. Margem zero desativa a histerese.

As alterações ficam em rascunho até clicar em **Salvar presets**. Salvar uma curva ativa tenta aplicá-la uma vez; arrastar os controles não envia comandos às ventoinhas. **Restaurar este preset** recupera os valores de fábrica no rascunho. Com mínimo em 100%, o preset mantém rotação máxima e oculta os controles de temperatura. Uma temperatura indisponível ou inválida leva à rotação máxima enquanto um preset personalizado está ativo.

## Proteções do controle

O serviço privilegiado valida a configuração e a assinatura do aplicativo antes de aceitar comandos. App e serviço precisam estar assinados por uma identidade Apple do mesmo time. A instância que iniciou o controle mantém uma concessão de oito segundos, renovada pelo app.

Quando o app sai, desconecta ou deixa de renovar essa concessão, o serviço tenta devolver o controle ao macOS. Falhas de restauração são tentadas novamente. Esses mecanismos dependem de o serviço e o hardware conseguirem responder; não substituem o gerenciamento térmico do sistema.

Para remover o app, use **Ajustes → Desativar controle**, encerre o Breeze e só então remova o aplicativo.

## Compilar e instalar

Instale o Xcode com suporte a Swift 6 e o [XcodeGen](https://github.com/yonaskolb/XcodeGen). O projeto Xcode é gerado a partir de `project.yml`; não há dependências externas de runtime.

Clone o projeto e escolha seu certificado de assinatura:

```sh
git clone git@github.com:paulorsv01/breeze.git
cd breeze
security find-identity -v -p codesigning
SIGNING_IDENTITY='<fingerprint do seu certificado>' CONFIGURATION=Release \
  bash script/build_and_run.sh --build-only
```

O script não escolhe certificados automaticamente. Ele compila o app e o helper, assina ambos e verifica suas assinaturas. O pacote fica em `build/DerivedData/Build/Products/Release/Breeze.app`.

Mova **Breeze.app** para **Aplicativos** e abra por lá antes de habilitar o controle. Na primeira vez, autorize o serviço em **Ajustes do Sistema → Geral → Itens de Início e Extensões**.

Para atualizar, encerre o Breeze e substitua o pacote inteiro em Aplicativos. Ao abrir, ele verifica o helper, gerencia a atualização do serviço e retoma o preset salvo. Sair do app mantém a preferência de controle habilitado; **Desativar controle** nos Ajustes a desliga. Veja os detalhes do [ciclo de vida do serviço](docs/helper-updates.md).

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

## Erros do SMC durante Performance

Uma falha na atualização da curva faz o Breeze retornar ao automático por segurança. O [diagnóstico do controle SMC](docs/smc-control.md) explica a recuperação condicional do modo manual, os dados úteis para novos relatos e os limites da validação por hardware.
