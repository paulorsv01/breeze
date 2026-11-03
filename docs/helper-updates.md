# Atualização do serviço

O Breeze verifica o helper antes de retomar o preset salvo. A resposta inclui a instalação carregada no início do processo: caminho do app e SHA-256 do executável e do plist. Assim, uma mudança no helper ou no caminho é detectada mesmo quando o número comercial da versão não muda. Helpers do release 1.0.0 não enviam essa informação e passam pela atualização uma vez.

Se a instalação já corresponde ao app, o serviço é reaproveitado. Caso contrário, o Breeze:

1. Restaura o modo automático e confirma a resposta. Se o helper estiver inacessível, invalida a conexão e aguarda o prazo da concessão de controle antes de substituir o registro.
2. Aguarda `SMAppService.unregister()` assíncrono concluir a remoção do processo.
3. Registra o helper do pacote atual com `SMAppService.register()`.
4. Confere novamente a autorização e a identidade retornada por XPC antes de permitir controle e retomar o preset salvo.

A atualização automática só ocorre em um serviço habilitado. Uma aprovação revogada não é contornada. Há uma tentativa de substituição por execução do app e uma verificação limitada; uma falha não dispara ciclos de reinstalação. Falhas comuns de comunicação depois de uma conexão validada continuam sendo tratadas como falhas de comunicação, sem reinstalar o serviço.

A primeira instalação continua exigindo aprovação do macOS. Nas atualizações, o app gerencia a troca usando sua identidade existente; a autorização efetiva é sempre consultada no sistema, sem prometer ausência de prompts em todo Mac. App e helper devem continuar assinados pelo mesmo time. A distribuição atual usa Apple Development pessoal e não é notarizada.

## Evidência

- O SDK da Apple, `ServiceManagement.framework/Headers/SMAppService.h`, exige novo registro se o plist ou executável mudar e recomenda desregistrar antes quando o executável muda. A conclusão da variante assíncrona indica que é seguro registrar novamente.
- [Stats: `SMCHelper.checkForUpdate`, `reinstall` e `uninstall`](https://github.com/exelban/stats/blob/master/Kit/helpers.swift) compara a versão em execução e atualiza o helper pelo próprio app, restaurando as ventoinhas antes da remoção.
- [Apple DTS: atualização de daemons](https://developer.apple.com/forums/thread/804561) também alerta para substituir executáveis por arquivos novos, sem sobrescrever arquivos em execução no mesmo inode.

A instalação deve substituir o pacote inteiro em `/Applications/Breeze.app`, preservando preferências. Não execute simultaneamente uma cópia do build e a instalada: ambas têm a mesma identidade de serviço.

## Validação local em 3 de novembro de 2026

Os 50 testes do núcleo passaram, incluindo helper antigo sem identidade, mudança de caminho, restauração recusada, aprovação pendente e limite de tentativas. O build Release foi assinado com o certificado pessoal do time `JP7Q26M5K2`.

Na instalação local, o app removeu o helper anterior e registrou o novo pelo SMAppService. O processo novo iniciou às 12:51:33; às 12:51:35 o log do helper confirmou `Applied preset: performance`. Esse comando só é enviado pelo fluxo de inicialização depois da comparação da instalação retornada por XPC. O Spotlight retornou apenas `/Applications/Breeze.app`.

A ferramenta de interface falhou durante a inspeção, então a confirmação foi feita por processos, registro do serviço e logs. Não foi possível observar pela ferramenta se houve algum prompt do macOS; este teste não comprova atualização sem prompts em todas as instalações.

## Sair e reconectar

Sair restaura o automático e fecha a conexão XPC; não remove o registro nem apaga o preset salvo. O app guarda separadamente a escolha de habilitar o controle (`fanControlEnabled`). Se essa escolha estiver ativa e o registro não existir na próxima abertura, tenta registrá-lo uma vez e então reconecta. Instalações existentes são reconhecidas pelo estado habilitado no macOS. Desativar o controle nos Ajustes limpa essa intenção após a remoção bem-sucedida; uma autorização pendente ou revogada continua dependendo da aprovação do macOS.

O painel inicia em estado de consulta, sem mostrar o botão de habilitar antes de verificar o serviço. Uma reconexão automática em andamento também não apresenta esse botão como ação necessária.
