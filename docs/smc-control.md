# Falha durante a atualização de Performance

Performance atualiza a curva periodicamente, mesmo sem novo clique no preset. Antes de escrever o RPM em `F%dTg`, o Breeze lê `F%dMd` (ou `F%dmd`) e confirma o modo manual. Se o firmware retomou o modo sistema, essa atualização precisa reativar o manual. Qualquer falha nessa sequência leva ao retorno de segurança ao automático.

O erro `F0Md: 0x10082` identifica uma recusa do firmware (`0x82`), mas a versão 1.0.0 não informava se a operação recusada era leitura ou escrita. A hipótese de retomada do modo sistema durante Performance foi reproduzida em teste com SMC simulado; a causa no Mac do relato ainda não foi confirmada em hardware.

## Correção condicional

A escrita direta continua sendo a primeira tentativa. Se ela falhar especificamente com `0x82`, a chave de modo ainda indicar sistema (`3`) e o SMC expuser `Ftst`, o Breeze solicita a liberação desse modo e espera até dez segundos antes de concluir a entrada no manual. Erros diferentes e hardware sem essa chave continuam falhando explicitamente.

`Ftst` é global. Ao restaurar, o Breeze primeiro devolve todas as ventoinhas controladas ao automático e só depois libera a chave global. Falhas de liberação permanecem pendentes para nova tentativa. Após reinício do helper, a recuperação também verifica essa chave. Fora da recuperação de reinício, o Breeze só libera um desbloqueio que tenha usado.

A concessão do cliente começa depois da aplicação inicial. Uma recuperação durante atualização periódica não renova essa concessão: se ela expirar durante a operação, o controlador retorna ao automático. O timeout XPC comporta a espera do firmware.

## Diagnóstico

As mensagens agora distinguem `open`, `read`, `write` e `enumerate`. Isso permite separar uma leitura recusada de uma falha ao reativar o modo manual. A consulta de metadados antes da escrita ainda pode falhar como `read`; `write` identifica o comando de escrita propriamente dito.

Outro controlador pode alterar o estado entre operações. Sua presença em uma captura não comprova interferência. A curva linear agora usa histerese configurável para reduzir oscilações de RPM durante o resfriamento. Isso não comprova nem resolve, por si só, a causa da recusa na chave de modo.

## Referências e limites

- [fanpro: códigos, modos e observações em hardware](https://github.com/omar16100/fanpro/blob/main/docs/smc_reference.md)
- [macos-smc-fan: sequência de desbloqueio e limites por modelo](https://github.com/agoodkind/macos-smc-fan/blob/main/docs/research.md)

Os testes cobrem retomada de modo durante atualização de temperatura, timeout, ausência da chave, erros não relacionados, liberação compartilhada e expiração da concessão. Não houve teste no MacBook Pro do relato; um novo erro deve ser acompanhado do modelo, versão do macOS, operação indicada e estado de outros controladores.
