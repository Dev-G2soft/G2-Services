# Script de implementacao para o G2-Online2

Implemente no repositorio `D:\GIT\G2-Online2` a integracao definitiva com o
G2-Services conforme este contrato. Preserve as rotas antigas para os Online
legados; somente o Online2 deve passar a usar as rotas novas.

## 1. Consulta de liberacao

Troque a URL padrao da consulta do Online2 para:

```text
GET {base_publica_g2services}/api/v1/liberacao?cpfcnpj={documento}&idCli={codigo_local_conhecido}
```

- `cpfcnpj`: CPF ou CNPJ local, somente digitos ou formatado.
- `idCli`: codigo central conhecido localmente; pode ser zero na primeira
  consulta.
- Nao envie `opc` para a rota nova.
- Mantenha timeout, limite de resposta, validacao HTTPS e ocultacao do
  documento nos erros.

Resposta de sucesso:

```json
{
  "metadados": { "status": "ok" },
  "data": {
    "ID_Cliente": 123,
    "categoria": "MENSAL",
    "Liberacao_sistema": "2026-09-10",
    "Liberacao_TEF": "2099-12-31",
    "Liberacao_temp": null,
    "apps": [
      {
        "id": 8,
        "data_add": "2026-08-07T10:00:00",
        "nome": "G2_UPDATE",
        "versao_atual": "24049",
        "versao_up": "24049",
        "link_download": "https://exemplo/arquivo.zip"
      }
    ],
    "telemetria": {
      "rota": "/api/v1/clientes/dados",
      "token": "64 caracteres hexadecimais",
      "expira_em": "2026-08-07T15:05:00"
    }
  }
}
```

O parser deve exigir `ID_Cliente`, as tres datas, `apps` e `telemetria`.
Datas nulas continuam aceitas. `Liberacao_temp` deve ser gravada no campo
homonimo de `g2mensagem.liberacao`; ela e apenas recebida do servidor e nao
deve ser calculada localmente.

## 2. Sincronizacao de `bancr.apps`

Substitua os campos escalares antigos `link` e `versao_update` pelo array
`apps`. Percorra todas as linhas recebidas dentro da mesma transacao usada
para aplicar a liberacao.

Para cada item, localize a linha exclusivamente por `nome`.

Se existir:

```sql
UPDATE bancr.apps
SET versao_up = :versao_up,
    link_download = CASE
      WHEN :tem_link = 1 THEN :link_download
      ELSE link_download
    END
WHERE nome = :nome;
```

Se nao existir:

```sql
INSERT INTO bancr.apps
  (id, data_add, nome, versao_up, link_download)
VALUES
  (:id, COALESCE(:data_add, NOW()), :nome, :versao_up, :link_download);
```

Regras obrigatorias:

- nunca apagar, renomear ou sobrescrever `nome` de uma linha existente;
- nunca sobrescrever `versao_atual` durante o recebimento;
- `versao_atual` continua sendo coletada e atualizada somente pela rotina
  local que examina os executaveis;
- se `link_download` vier nulo ou vazio para uma linha existente, preservar o
  link local existente;
- se o `id` central conflitar com outro registro local, inserir usando o
  auto incremento/local disponivel e manter `nome` como chave logica;
- nao excluir aplicativos locais que nao vierem na resposta;
- aceitar automaticamente novos nomes adicionados futuramente no servidor.

Remova do fluxo novo a gravacao de `link` e `versao_update` no arquivo INI.
Esses dados passam a pertencer exclusivamente a `bancr.apps`.

## 3. Envio dos dados da maquina

Depois de confirmar localmente a liberacao e os aplicativos, monte o JSON de
telemetria ja existente. Forme a URL de envio preservando esquema, host e
porta da URL de liberacao e substituindo o caminho pela `telemetria.rota`.

```text
POST {base_publica_g2services}/api/v1/clientes/dados
Authorization: Bearer {telemetria.token}
Content-Type: application/json; charset=utf-8
```

O payload continua no schema 1 e deve conter:

- identificacao central e local do cliente;
- identificador estavel e nome da maquina;
- perfil, IP, hardware, discos e Windows;
- versoes dos sistemas instalados;
- certificado digital;
- ultima venda.

A chave vale cinco minutos e pode ser usada uma unica vez. Em falha de envio,
nao reutilize uma chave vencida ou ja aceita: faça nova consulta de liberacao
no proximo ciclo para obter outra chave.

## 4. Compatibilidade e validacao

- Nao modificar nem remover o endpoint PHP legado.
- Nao modificar as rotas antigas configuradas nos Online legados.
- A nova integracao pertence somente ao Online2.
- Aplicar liberacao, `Liberacao_temp`, identificacao central e `apps` em uma
  unica transacao local.
- Enviar telemetria somente depois do commit local.
- Compilar `Debug Win32` e executar os testes/self-test existentes.
- Validar pelo menos: gratuito, mensal com parcela aberta, liberacao
  temporaria, aplicativo existente, aplicativo novo, link nulo, duas maquinas
  do mesmo cliente e token expirado.

