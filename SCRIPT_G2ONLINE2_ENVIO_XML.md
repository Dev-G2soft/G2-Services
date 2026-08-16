# Script de implementacao: envio de XML do G2-Online2 para o G2-Services

Use estas instrucoes no repositorio `D:\GIT\G2-Online2`.

## Objetivo

Implementar no G2-Online2 o envio opcional dos XMLs armazenados localmente em
`bancr.xmls_geradas` para o G2-Services. O Services ja possui a rota legada
`POST /upload`, que recebe um XML em Base64 e cria o arquivo na pasta do CNPJ.

Nao alterar o G2-Services, nao criar uma rota nova para XML e nao modificar o
comportamento dos programas antigos. Os Online antigos continuarao usando
`POST /upload` exatamente como usam hoje.

## Restricoes obrigatorias

- Nao executar DDL nem criar/alterar tabelas automaticamente.
- Nao apagar registros ou o conteudo XML de `xmls_geradas`.
- Nao alterar `importa_servidor`; esse campo pertence ao fluxo PDV -> servidor
  local do Online2.
- Usar exclusivamente `importa_nuvem` para controlar o envio ao G2-Services.
- Nao sobrescrever `status`, `status_nfe`, `msg`, `chave` ou `xml`.
- Nao manter transacao de banco aberta durante a chamada HTTP.
- Nao criar outro cliente HTTP: reutilizar `TOnline2WinHttp` de
  `uOnline2.Http.WinHttp.pas`.
- Reutilizar e completar o contrato `TOnline2XmlNuvemContrato` e a funcao
  `XmlNuvemHabilitado`, ja existentes em
  `uOnline2.ServicosCentrais.Contratos.pas`.
- Nao reaproveitar a marcacao da tarefa `TOnline2TarefaTransmissaoXmls`: ela
  pertence ao fluxo atual de sincronizacao PDV -> servidor.

## Configuracao local

Criar uma chave local em `bancr.configuracoes2`:

```text
nome: ONLINE2_XML_NUVEM_ATIVO
valor1: 0 ou 1
```

Regras:

- chave ausente, vazia ou diferente de `1`: servico desativado;
- `1`: servico ativado;
- essa configuracao e local e nunca deve ser sincronizada ou sobrescrita por
  configuracao recebida do servidor central;
- `XmlNuvemHabilitado` deve consultar essa chave e retornar `False` em qualquer
  erro, registrando o erro no log sem interromper as outras tarefas.

## Onde executar

Criar uma tarefa nova e independente, por exemplo
`TOnline2TarefaEnvioXmlG2Services`, baseada em `TOnline2TarefaBase`.

Registrar a tarefa apenas para o perfil `opServidor`. Assim, o envio ocorre
uma unica vez a partir do banco do servidor local do cliente e nao uma vez em
cada PDV. A tarefa existente de transmissao de XML dos PDVs continua intacta.

Sugestao de ciclo:

- executar a cada 60 segundos quando habilitada;
- processar no maximo 20 XMLs por ciclo;
- enviar um XML por requisicao, pois `/upload` aceita somente um documento;
- respeitar cancelamento/parada da tarefa entre os itens.

## Selecao dos XMLs

Antes de iniciar, conferir por metadados se as colunas `importa_servidor`,
`importa_nuvem` e `data_envio` existem. Se alguma nao existir, apenas registrar
que a estrutura precisa ser atualizada e desativar esta tarefa. Nao executar
`ALTER TABLE`.

Selecionar em ordem de `codigo`, com limite de 20:

```sql
SELECT codigo, modelo, chave, xml
FROM bancr.xmls_geradas
WHERE COALESCE(importa_servidor, 0) = 1
  AND COALESCE(importa_nuvem, 0) = 0
  AND modelo IN (55, 65)
  AND UPPER(TRIM(COALESCE(status, ''))) = 'ENVIADA'
  AND LENGTH(TRIM(COALESCE(chave, ''))) = 44
  AND TRIM(COALESCE(xml, '')) <> ''
ORDER BY codigo
LIMIT 20;
```

Se a versao instalada da tabela nao tiver alguma dessas colunas, nao inventar
uma migracao. Registrar a incompatibilidade e nao enviar ate a estrutura ser
validada.

Enviar somente NF-e/NFC-e autorizada, modelos 55 e 65. Nao enviar XML de
cancelamento ou inutilizacao por esta rotina, porque a rota atual `/upload`
carrega um documento fiscal e extrai a chave de `procNFe`.

## URL do Services

Usar a mesma origem configurada para a liberacao: preservar esquema, host e
porta e substituir somente o caminho por `/upload`.

Exemplo:

```text
Liberacao: https://servidor.exemplo/api/v1/liberacao
XML:       https://servidor.exemplo/upload
```

Nao fixar dominio, IP ou porta no fonte. Manter as mesmas regras de timeout,
limite de resposta, HTTPS e User-Agent usadas pelas demais chamadas centrais.

## Contrato HTTP existente

Requisicao:

```http
POST /upload HTTP/1.1
Content-Type: application/json; charset=utf-8
User-Agent: G2-Online2

{"dados":"XML_COMPLETO_EM_BASE64"}
```

O campo `xml` do banco contem XML em texto. Converter o XML completo para
bytes UTF-8 e depois para Base64 sem quebras de linha. Criar o corpo com
`TJSONObject`; nao concatenar JSON manualmente.

Exemplo Delphi:

```pascal
var
  LJson: TJSONObject;
  LBase64: string;
begin
  LBase64 := TNetEncoding.Base64.EncodeBytesToString(
    TEncoding.UTF8.GetBytes(LXml));

  LJson := TJSONObject.Create;
  try
    LJson.AddPair('dados', LBase64);
    LCorpo := LJson.ToJSON;
  finally
    LJson.Free;
  end;
end;
```

Resposta aceita pela rota atual:

```json
{"status":"OK","motivo":"Executado"}
```

Considerar o envio aceito somente quando as duas condicoes forem verdadeiras:

1. HTTP retornou codigo de sucesso 2xx;
2. o JSON foi analisado com sucesso e `status` e igual a `OK`, ignorando
   maiusculas/minusculas.

Timeout, resposta nao-2xx, JSON invalido ou `status` diferente de `OK` sao
falhas. Nesses casos, manter `importa_nuvem = 0` para tentar novamente em
outro ciclo.

## Confirmacao local

Depois de receber a confirmacao HTTP, abrir uma transacao curta e executar:

```sql
UPDATE bancr.xmls_geradas
SET importa_nuvem = 1,
    data_envio = COALESCE(data_envio, NOW())
WHERE codigo = :codigo
  AND COALESCE(importa_nuvem, 0) = 0
  AND chave = :chave;
```

Confirmar a transacao somente se uma linha for afetada. Nao alterar nenhum
outro campo. A requisicao HTTP deve ocorrer antes e fora dessa transacao.

O endpoint usa a chave como nome do arquivo. Portanto, se houver uma falha de
rede depois de o Services receber o documento, a repeticao substitui o mesmo
arquivo em vez de criar outro nome. Mesmo assim, nunca marcar como enviado sem
a resposta valida descrita acima.

Observacao: hoje `/upload` responde antes de terminar a gravacao assincrona no
disco. Portanto, `status=OK` significa que o Services aceitou a solicitacao,
nao que o arquivo ja foi confirmado no HDD. Nao mudar isso neste trabalho.

## Logs

Registrar sem incluir o XML nem o Base64:

- inicio e fim do ciclo;
- quantidade selecionada, enviada e com erro;
- `codigo`, modelo e chave de cada tentativa;
- codigo HTTP e motivo resumido da falha;
- ausencia da coluna/configuracao necessaria.

Nunca registrar o conteudo integral do XML ou do Base64.

## Testes obrigatorios

1. Configuracao ausente ou `0`: nenhuma consulta/envio de XML.
2. Configuracao `1`: a tarefa processa um XML elegivel.
3. Registro ainda nao recebido do PDV (`importa_servidor=0`) e ignorado.
4. Modelos diferentes de 55/65, status diferente de `ENVIADA`, chave invalida
   ou XML vazio sao ignorados.
5. HTTP 500, timeout ou JSON invalido: `importa_nuvem` continua `0`.
6. HTTP 200 com `status` diferente de `OK`: continua `0`.
7. HTTP 200 com `status=OK`: apenas `importa_nuvem` passa para `1` e
   `data_envio` e preenchida se ainda estiver nula.
8. Confirmar que `importa_servidor`, `status`, `msg`, `chave` e `xml` nao foram
   alterados.
9. Confirmar limite de 20 itens e retomada no ciclo seguinte.
10. Confirmar que nenhuma transacao permanece aberta durante a rede.
11. Compilar `Debug Win32` e executar os testes/self-test existentes.

## Resultado esperado

Quando `ONLINE2_XML_NUVEM_ATIVO=1`, o Online2 servidor envia gradualmente os
XMLs autorizados ainda nao enviados para a rota existente do G2-Services. Os
clientes antigos continuam inalterados, o fluxo PDV -> servidor continua
usando `importa_servidor`, e o envio central passa a ser controlado apenas por
`importa_nuvem`.
