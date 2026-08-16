unit uDadosClientes;

interface

uses
  System.SysUtils;

type
  EDadosClientes = class(Exception)
  private
    FStatusHttp: Integer;
  public
    constructor Create(const AStatusHttp: Integer; const AMensagem: string);
    property StatusHttp: Integer read FStatusHttp;
  end;

  TDadosClientes = class
  strict private
    class function CriarToken: string; static;
    class function HashToken(const AToken: string): string; static;
  public
    class procedure PrepararBanco; static;
    class function RespostaErro(const AMensagem: string): string; static;
    class function ConsultarLiberacao(const ADocumento: string;
      const AIdClienteLocal: Integer): string; static;
    class function Receber(const AAuthorization, AJson: string): string; static;
  end;

implementation

uses
  System.Classes,
  System.DateUtils,
  System.Hash,
  System.JSON,
  Data.DB,
  Horse,
  Winapi.Windows,
  ZDataset,
  uDM;

const
  BANCO_DADOS_CLIENTES = 'Dados_Clientes';
  TABELA_MAQUINAS = 'Dados_Clientes.clientes';
  TABELA_CHAVES = 'Dados_Clientes.chaves_temporarias';
  TOKEN_VALIDADE_SEGUNDOS_PADRAO = 300;
  ROTA_TELEMETRIA = '/api/v1/clientes/dados';
  LIMITE_JSON_BYTES = 1024 * 1024;
  BCRYPT_USE_SYSTEM_PREFERRED_RNG = $00000002;

function BCryptGenRandom(hAlgorithm: Pointer; pbBuffer: PByte;
  cbBuffer, dwFlags: ULONG): LongInt; stdcall;
  external 'bcrypt.dll' name 'BCryptGenRandom';

var
  GBancoPreparado: Boolean;
  GLockBanco: TObject;

function SomenteDigitos(const ATexto: string): string;
var
  C: Char;
begin
  Result := '';
  for C in ATexto do
    if CharInSet(C, ['0'..'9']) then
      Result := Result + C;
end;

function JsonErro(const AMensagem: string): string;
var
  Raiz: TJSONObject;
begin
  Raiz := TJSONObject.Create;
  try
    Raiz.AddPair('metadados', TJSONObject.Create
      .AddPair('status', 'erro')
      .AddPair('motivo', AMensagem));
    Result := Raiz.ToJSON;
  finally
    Raiz.Free;
  end;
end;

function JsonSucesso(const AMensagem: string): string;
var
  Raiz: TJSONObject;
begin
  Raiz := TJSONObject.Create;
  try
    Raiz.AddPair('metadados', TJSONObject.Create
      .AddPair('status', 'ok')
      .AddPair('motivo', AMensagem));
    Result := Raiz.ToJSON;
  finally
    Raiz.Free;
  end;
end;

function ObjetoObrigatorio(AObjeto: TJSONObject;
  const ANome: string): TJSONObject;
var
  Valor: TJSONValue;
begin
  Valor := AObjeto.GetValue(ANome);
  if not (Valor is TJSONObject) then
    raise EDadosClientes.Create(400,
      'O objeto "' + ANome + '" nao foi informado corretamente.');
  Result := TJSONObject(Valor);
end;

function TextoJson(AObjeto: TJSONObject; const ANome: string;
  const ATamanhoMaximo: Integer): string;
var
  Valor: TJSONValue;
begin
  Result := '';
  Valor := AObjeto.GetValue(ANome);
  if (Valor = nil) or (Valor is TJSONNull) then
    Exit;
  if not (Valor is TJSONString) then
    raise EDadosClientes.Create(400,
      'O campo "' + ANome + '" possui tipo invalido.');
  Result := Trim(Valor.Value);
  if Length(Result) > ATamanhoMaximo then
    raise EDadosClientes.Create(400,
      'O campo "' + ANome + '" excede o tamanho permitido.');
end;

function InteiroJson(AObjeto: TJSONObject; const ANome: string): Integer;
var
  Valor: TJSONValue;
begin
  Valor := AObjeto.GetValue(ANome);
  if (Valor = nil) or (not TryStrToInt(Valor.Value, Result)) then
    raise EDadosClientes.Create(400,
      'O campo "' + ANome + '" nao contem um inteiro valido.');
end;

function DataHoraJson(AObjeto: TJSONObject; const ANome: string;
  out AValor: TDateTime): Boolean;
var
  Texto: string;
begin
  Result := False;
  AValor := 0;
  Texto := TextoJson(AObjeto, ANome, 40);
  if Texto = '' then
    Exit;
  try
    AValor := ISO8601ToDate(Texto, False);
    Result := True;
  except
    raise EDadosClientes.Create(400,
      'O campo "' + ANome + '" nao contem data e hora validas.');
  end;
end;

procedure DefinirDataOpcional(AQuery: TZQuery; const AParametro: string;
  const AInformada: Boolean; const AValor: TDateTime);
begin
  if AInformada then
    AQuery.ParamByName(AParametro).AsDateTime := AValor
  else
    AQuery.ParamByName(AParametro).Clear;
end;

{ EDadosClientes }

constructor EDadosClientes.Create(const AStatusHttp: Integer;
  const AMensagem: string);
begin
  inherited Create(AMensagem);
  FStatusHttp := AStatusHttp;
end;

{ TDadosClientes }

class function TDadosClientes.CriarToken: string;
const
  HEX: array[0..15] of Char = '0123456789abcdef';
var
  Bytes: array[0..31] of Byte;
  I: Integer;
begin
  if BCryptGenRandom(nil, @Bytes[0], SizeOf(Bytes),
       BCRYPT_USE_SYSTEM_PREFERRED_RNG) < 0 then
    raise EDadosClientes.Create(500,
      'Nao foi possivel gerar a chave temporaria de seguranca.');
  SetLength(Result, SizeOf(Bytes) * 2);
  for I := 0 to High(Bytes) do
  begin
    Result[(I * 2) + 1] := HEX[Bytes[I] shr 4];
    Result[(I * 2) + 2] := HEX[Bytes[I] and $0F];
  end;
  FillChar(Bytes, SizeOf(Bytes), 0);
end;

class function TDadosClientes.HashToken(const AToken: string): string;
begin
  Result := LowerCase(THashSHA2.GetHashString(AToken));
end;

class procedure TDadosClientes.PrepararBanco;
var
  Query: TZQuery;
begin
  TMonitor.Enter(GLockBanco);
  try
    if GBancoPreparado then
      Exit;
    if not DM.ZConexaoBancR.Connected then
      DM.ZConexaoBancR.Connect;
    Query := TZQuery.Create(nil);
    try
      Query.Connection := DM.ZConexaoBancR;
      Query.SQL.Text :=
        'CREATE DATABASE IF NOT EXISTS ' + BANCO_DADOS_CLIENTES +
        ' CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci';
      Query.ExecSQL;
      Query.SQL.Text :=
        'CREATE TABLE IF NOT EXISTS ' + TABELA_MAQUINAS + ' (' +
        'id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,' +
        'codigo_cliente INT NOT NULL,' +
        'codigo_cadastro_local INT NULL,' +
        'cnpj VARCHAR(14) NULL,' +
        'coletado_em DATETIME NULL,' +
        'maquina_identificador VARCHAR(64) NOT NULL,' +
        'maquina_nome VARCHAR(100) NULL,' +
        'perfil VARCHAR(20) NULL,' +
        'ip_principal VARCHAR(45) NULL,' +
        'online2_versao VARCHAR(50) NULL,' +
        'ultima_venda_em DATETIME NULL,' +
        'dados_json LONGTEXT NULL,' +
        'criado_em DATETIME NOT NULL,' +
        'atualizado_em DATETIME NOT NULL,' +
        'PRIMARY KEY (id),' +
        'UNIQUE KEY uk_cliente_maquina ' +
        '(codigo_cliente,maquina_identificador),' +
        'KEY idx_cliente (codigo_cliente)' +
        ') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4';
      Query.ExecSQL;
      Query.SQL.Text :=
        'CREATE TABLE IF NOT EXISTS ' + TABELA_CHAVES + ' (' +
        'id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,' +
        'codigo_cliente INT NOT NULL,' +
        'cnpj VARCHAR(14) NOT NULL,' +
        'chave_hash CHAR(64) NOT NULL,' +
        'chave_criada_em DATETIME NOT NULL,' +
        'chave_expira_em DATETIME NOT NULL,' +
        'chave_utilizada_em DATETIME NULL,' +
        'PRIMARY KEY (id),' +
        'UNIQUE KEY uk_chave_hash (chave_hash),' +
        'KEY idx_cliente_expiracao ' +
        '(codigo_cliente,chave_expira_em)' +
        ') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4';
      Query.ExecSQL;
      GBancoPreparado := True;
    finally
      Query.Free;
    end;
  finally
    TMonitor.Exit(GLockBanco);
  end;
end;

class function TDadosClientes.ConsultarLiberacao(const ADocumento: string;
  const AIdClienteLocal: Integer): string;
var
  App: TJSONObject;
  Apps: TJSONArray;
  Categoria: string;
  CodigoLiberacao: Integer;
  CodigoCliente: Integer;
  DataSistema: TDateTime;
  DataSistemaInformada: Boolean;
  DataTemporaria: TDateTime;
  DataTemporariaInformada: Boolean;
  DataTef: TDateTime;
  Documento: string;
  EmTransacao: Boolean;
  JsonData: TJSONObject;
  JsonRaiz: TJSONObject;
  JsonTelemetria: TJSONObject;
  ExpiraEm: TDateTime;
  Query: TZQuery;
  Token: string;
begin
  PrepararBanco;
  Apps := TJSONArray.Create;
  CodigoCliente := 0;
  CodigoLiberacao := 0;
  DataSistema := 0;
  DataTemporaria := 0;
  DataTemporariaInformada := False;
  { TODO: substituir a data fixa pelo calculo real da liberacao do TEF. }
  DataTef := EncodeDate(2099, 12, 31);
  ExpiraEm := 0;
  Documento := SomenteDigitos(ADocumento);
  if not (Length(Documento) in [11, 14]) then
    raise EDadosClientes.Create(400,
      'O CPF ou CNPJ informado e invalido.');
  if AIdClienteLocal < 0 then
    raise EDadosClientes.Create(400,
      'O codigo local do cliente e invalido.');

  Token := '';
  try
    TMonitor.Enter(GLockBanco);
    try
      if not DM.ZConexaoBancR.Connected then
        DM.ZConexaoBancR.Connect;
      Query := TZQuery.Create(nil);
      try
        Query.Connection := DM.ZConexaoBancR;
        EmTransacao := False;
        try
          DM.ZConexaoBancR.StartTransaction;
          EmTransacao := True;
          Query.SQL.Text :=
            'SELECT c.COD_Aluno AS ID_Cliente,c.Categoria,' +
            'l.Codigo AS Codigo_liberacao,l.Liberacao_sistema,' +
            'l.Liberacao_temp ' +
            'FROM bancr.cadastro c ' +
            'LEFT JOIN g2mensagem.liberacao l ON l.Codigo=(' +
            'SELECT MAX(l2.Codigo) FROM g2mensagem.liberacao l2 ' +
            'WHERE l2.ID_Cliente=c.COD_Aluno) ' +
            'WHERE (REPLACE(REPLACE(REPLACE(REPLACE(' +
            'TRIM(COALESCE(c.CNPJ,'''')),''.'',''''),''-'',''''),''/'',''''),'' '','''')=:doc ' +
            'OR REPLACE(REPLACE(REPLACE(REPLACE(' +
            'TRIM(COALESCE(c.CPF,'''')),''.'',''''),''-'',''''),''/'',''''),'' '','''')=:doc) ' +
            'ORDER BY (c.COD_Aluno=:id_local) DESC,c.COD_Aluno ' +
            'LIMIT 1 FOR UPDATE';
          Query.ParamByName('doc').AsString := Documento;
          Query.ParamByName('id_local').AsInteger := AIdClienteLocal;
          Query.Open;
          if Query.IsEmpty then
            raise EDadosClientes.Create(404,
              'Cliente nao localizado para o CPF ou CNPJ informado.');

          CodigoCliente := Query.FieldByName('ID_Cliente').AsInteger;
          Categoria := Trim(Query.FieldByName('Categoria').AsString);
          if not Query.FieldByName('Codigo_liberacao').IsNull then
            CodigoLiberacao :=
              Query.FieldByName('Codigo_liberacao').AsInteger;
          DataSistemaInformada :=
            not Query.FieldByName('Liberacao_sistema').IsNull;
          if DataSistemaInformada then
            DataSistema :=
              Query.FieldByName('Liberacao_sistema').AsDateTime;
          DataTemporariaInformada :=
            not Query.FieldByName('Liberacao_temp').IsNull;
          if DataTemporariaInformada then
            DataTemporaria :=
              Query.FieldByName('Liberacao_temp').AsDateTime;

          Query.Close;
          if SameText(Categoria, 'GRATUITO') then
          begin
            { Cliente gratuito nao consulta contas a receber. }
            DataSistema := EncodeDate(2085, 12, 29);
          end
          else
          begin
            Query.SQL.Text :=
              'SELECT MIN(p.vencimento) AS primeiro_vencimento ' +
              'FROM bancr.contas_a_receber_pagamento p ' +
              'INNER JOIN bancr.contas_a_receber r ' +
              'ON r.Codigo=p.Cod_Contas_a_receber ' +
              'WHERE r.Cod_cliente=:codigo ' +
              'AND UPPER(TRIM(COALESCE(p.Pago,''NAO'')))<>''SIM'' ' +
              'AND COALESCE(p.Cancelado,0)=0 ' +
              'AND UPPER(TRIM(r.Tipo_cobranca)) IN (' +
              '''MENSALIDADE'',''MENSALIDADE E TEF'',' +
              '''TEF E MENSALIDADE'')';
            Query.ParamByName('codigo').AsInteger := CodigoCliente;
            Query.Open;
            if not Query.FieldByName('primeiro_vencimento').IsNull then
            begin
              DataSistema := IncMonth(
                Query.FieldByName('primeiro_vencimento').AsDateTime, 1);
              DataSistemaInformada := True;
            end;
            Query.Close;
            if not DataSistemaInformada then
              raise EDadosClientes.Create(409,
                'O cliente nao possui mensalidade aberta nem liberacao cadastrada.');
          end;

          if CodigoLiberacao > 0 then
          begin
            Query.SQL.Text :=
              'UPDATE g2mensagem.liberacao SET ' +
              'Liberacao_sistema=:sistema,Liberacao_TEF=:tef,' +
              'Operador=''0000 - G2-SERVICES'',' +
              'Obs=''Recalculado automaticamente pelo G2-Services'',' +
              'data_verificacao=NOW(),data_update=NOW() ' +
              'WHERE Codigo=:codigo_liberacao';
            Query.ParamByName('codigo_liberacao').AsInteger :=
              CodigoLiberacao;
          end
          else
          begin
            Query.SQL.Text :=
              'INSERT INTO g2mensagem.liberacao (' +
              'ID_Cliente,Liberacao_sistema,Liberacao_TEF,Operador,Obs,' +
              'data_verificacao,data_update) VALUES (' +
              ':codigo_cliente,:sistema,:tef,''0000 - G2-SERVICES'',' +
              '''Criado automaticamente pelo G2-Services'',NOW(),NOW())';
            Query.ParamByName('codigo_cliente').AsInteger := CodigoCliente;
          end;
          Query.ParamByName('sistema').AsDateTime := DataSistema;
          Query.ParamByName('tef').AsDateTime := DataTef;
          Query.ExecSQL;

          Token := CriarToken;
          ExpiraEm := IncSecond(Now, TOKEN_VALIDADE_SEGUNDOS_PADRAO);
          Query.SQL.Text :=
            'INSERT INTO ' + TABELA_CHAVES + ' (' +
            'codigo_cliente,cnpj,chave_hash,chave_criada_em,' +
            'chave_expira_em,chave_utilizada_em) VALUES (' +
            ':codigo,:cnpj,:hash,NOW(),:expira,NULL)';
          Query.ParamByName('codigo').AsInteger := CodigoCliente;
          Query.ParamByName('cnpj').AsString := Documento;
          Query.ParamByName('hash').AsString := HashToken(Token);
          Query.ParamByName('expira').AsDateTime := ExpiraEm;
          Query.ExecSQL;

          Query.SQL.Text :=
            'SELECT id,data_add,nome,versao_atual,versao_up,' +
            'link_download FROM bancr.apps ORDER BY id';
          Query.Open;
          while not Query.Eof do
          begin
            App := TJSONObject.Create;
            App.AddPair('id', TJSONNumber.Create(
              Query.FieldByName('id').AsInteger));
            App.AddPair('nome', Query.FieldByName('nome').AsString);
            if Query.FieldByName('data_add').IsNull then
              App.AddPair('data_add', TJSONNull.Create)
            else
              App.AddPair('data_add', FormatDateTime(
                'yyyy-mm-dd"T"hh:nn:ss',
                Query.FieldByName('data_add').AsDateTime));
            if Query.FieldByName('versao_atual').IsNull then
              App.AddPair('versao_atual', TJSONNull.Create)
            else
              App.AddPair('versao_atual',
                Query.FieldByName('versao_atual').AsString);
            if Query.FieldByName('versao_up').IsNull then
              App.AddPair('versao_up', TJSONNull.Create)
            else
              App.AddPair('versao_up',
                Query.FieldByName('versao_up').AsString);
            if Query.FieldByName('link_download').IsNull then
              App.AddPair('link_download', TJSONNull.Create)
            else
              App.AddPair('link_download',
                Query.FieldByName('link_download').AsString);
            Apps.AddElement(App);
            Query.Next;
          end;

          DM.ZConexaoBancR.Commit;
          EmTransacao := False;
        except
          if EmTransacao then
            DM.ZConexaoBancR.Rollback;
          raise;
        end;
      finally
        Query.Free;
      end;
    finally
      TMonitor.Exit(GLockBanco);
    end;

    JsonRaiz := TJSONObject.Create;
    try
      JsonRaiz.AddPair('metadados', TJSONObject.Create
        .AddPair('status', 'ok'));
      JsonData := TJSONObject.Create;
      JsonRaiz.AddPair('data', JsonData);
      JsonData.AddPair('ID_Cliente', TJSONNumber.Create(CodigoCliente));
      JsonData.AddPair('categoria', Categoria);
      JsonData.AddPair('Liberacao_sistema',
        FormatDateTime('yyyy-mm-dd', DataSistema));
      JsonData.AddPair('Liberacao_TEF',
        FormatDateTime('yyyy-mm-dd', DataTef));
      if DataTemporariaInformada then
        JsonData.AddPair('Liberacao_temp',
          FormatDateTime('yyyy-mm-dd', DataTemporaria))
      else
        JsonData.AddPair('Liberacao_temp', TJSONNull.Create);
      JsonData.AddPair('apps', Apps);
      Apps := nil;

      JsonTelemetria := TJSONObject.Create;
      JsonTelemetria.AddPair('rota', ROTA_TELEMETRIA);
      JsonTelemetria.AddPair('token', Token);
      JsonTelemetria.AddPair('expira_em', FormatDateTime(
        'yyyy-mm-dd"T"hh:nn:ss', ExpiraEm));
      JsonData.AddPair('telemetria', JsonTelemetria);
      Result := JsonRaiz.ToJSON;
    finally
      JsonRaiz.Free;
      Token := '';
    end;
  finally
    Apps.Free;
    Token := '';
  end;
end;

class function TDadosClientes.Receber(const AAuthorization,
  AJson: string): string;
var
  Cliente: TJSONObject;
  CodigoCliente: Integer;
  CodigoLocal: Integer;
  ColetadoEm: TDateTime;
  Cnpj: string;
  EmTransacao: Boolean;
  Hash: string;
  Maquina: TJSONObject;
  MaquinaId: string;
  MaquinaNome: string;
  Online2Versao: string;
  Perfil: string;
  IpPrincipal: string;
  Query: TZQuery;
  Raiz: TJSONValue;
  RaizObjeto: TJSONObject;
  Schema: Integer;
  Token: string;
  TokenId: Int64;
  UltimaVenda: TJSONObject;
  UltimaVendaEm: TDateTime;
  UltimaVendaInformada: Boolean;
begin
  PrepararBanco;
  if Length(TEncoding.UTF8.GetBytes(AJson)) > LIMITE_JSON_BYTES then
    raise EDadosClientes.Create(413,
      'O JSON recebido excede o limite de 1 MB.');
  if not SameText(Copy(Trim(AAuthorization), 1, 7), 'Bearer ') then
    raise EDadosClientes.Create(401,
      'A chave temporaria nao foi informada.');
  Token := Trim(Copy(Trim(AAuthorization), 8, MaxInt));
  if Length(Token) <> 64 then
    raise EDadosClientes.Create(401,
      'A chave temporaria e invalida ou expirou.');

  Raiz := TJSONObject.ParseJSONValue(AJson);
  if not (Raiz is TJSONObject) then
  begin
    Raiz.Free;
    raise EDadosClientes.Create(400, 'O corpo da requisicao nao e um JSON valido.');
  end;
  try
    RaizObjeto := TJSONObject(Raiz);
    Schema := InteiroJson(RaizObjeto, 'schema');
    if Schema <> 1 then
      raise EDadosClientes.Create(400,
        'A versao do JSON de dados do cliente nao e suportada.');
    if not DataHoraJson(RaizObjeto, 'coletado_em', ColetadoEm) then
      raise EDadosClientes.Create(400,
        'A data de coleta nao foi informada.');

    Cliente := ObjetoObrigatorio(RaizObjeto, 'cliente');
    CodigoCliente := InteiroJson(Cliente, 'codigo_interno');
    CodigoLocal := InteiroJson(Cliente, 'codigo_cadastro_local');
    Cnpj := SomenteDigitos(TextoJson(Cliente, 'cnpj', 20));
    if (CodigoCliente <= 0) or (CodigoLocal < 0) or
       (not (Length(Cnpj) in [11, 14])) then
      raise EDadosClientes.Create(400,
        'A identificacao do cliente possui valores invalidos.');

    Maquina := ObjetoObrigatorio(RaizObjeto, 'maquina');
    MaquinaId := TextoJson(Maquina, 'identificador', 64);
    MaquinaNome := TextoJson(Maquina, 'nome', 100);
    Perfil := TextoJson(Maquina, 'perfil', 20);
    IpPrincipal := TextoJson(Maquina, 'ip_principal', 45);
    Online2Versao := TextoJson(Maquina, 'online2_versao', 50);
    if MaquinaId = '' then
      raise EDadosClientes.Create(400,
        'O identificador da maquina nao foi informado.');
    ObjetoObrigatorio(RaizObjeto, 'sistemas');
    ObjetoObrigatorio(RaizObjeto, 'certificado_digital');
    UltimaVenda := ObjetoObrigatorio(RaizObjeto, 'ultima_venda');
    UltimaVendaInformada :=
      DataHoraJson(UltimaVenda, 'data_hora', UltimaVendaEm);

    Hash := HashToken(Token);
    Token := '';
    TMonitor.Enter(GLockBanco);
    try
      if not DM.ZConexaoBancR.Connected then
        DM.ZConexaoBancR.Connect;
      Query := TZQuery.Create(nil);
      try
        Query.Connection := DM.ZConexaoBancR;
        EmTransacao := False;
        try
          DM.ZConexaoBancR.StartTransaction;
          EmTransacao := True;
          Query.SQL.Text :=
            'SELECT id FROM ' + TABELA_CHAVES + ' ' +
            'WHERE codigo_cliente=:codigo AND cnpj=:cnpj ' +
            'AND chave_hash=:hash AND chave_utilizada_em IS NULL ' +
            'AND chave_expira_em>=NOW() LIMIT 1 FOR UPDATE';
          Query.ParamByName('codigo').AsInteger := CodigoCliente;
          Query.ParamByName('cnpj').AsString := Cnpj;
          Query.ParamByName('hash').AsString := Hash;
          Query.Open;
          if Query.IsEmpty then
            raise EDadosClientes.Create(401,
              'A chave temporaria e invalida, expirou ou ja foi utilizada.');
          TokenId := Query.FieldByName('id').AsLargeInt;
          Query.Close;

          Query.SQL.Text :=
            'INSERT INTO ' + TABELA_MAQUINAS + ' (' +
            'codigo_cliente,codigo_cadastro_local,cnpj,coletado_em,' +
            'maquina_identificador,maquina_nome,perfil,ip_principal,' +
            'online2_versao,ultima_venda_em,dados_json,' +
            'criado_em,atualizado_em) VALUES (' +
            ':codigo,:codigo_local,:cnpj,:coletado,:maquina_id,' +
            ':maquina_nome,:perfil,:ip,:online2_versao,:ultima_venda,' +
            ':json,NOW(),NOW()) ON DUPLICATE KEY UPDATE ' +
            'codigo_cadastro_local=VALUES(codigo_cadastro_local),' +
            'cnpj=VALUES(cnpj),coletado_em=VALUES(coletado_em),' +
            'maquina_nome=VALUES(maquina_nome),perfil=VALUES(perfil),' +
            'ip_principal=VALUES(ip_principal),' +
            'online2_versao=VALUES(online2_versao),' +
            'ultima_venda_em=VALUES(ultima_venda_em),' +
            'dados_json=VALUES(dados_json),atualizado_em=NOW()';
          Query.ParamByName('codigo_local').AsInteger := CodigoLocal;
          Query.ParamByName('cnpj').AsString := Cnpj;
          Query.ParamByName('coletado').AsDateTime := ColetadoEm;
          Query.ParamByName('maquina_id').AsString := MaquinaId;
          Query.ParamByName('maquina_nome').AsString := MaquinaNome;
          Query.ParamByName('perfil').AsString := Perfil;
          Query.ParamByName('ip').AsString := IpPrincipal;
          Query.ParamByName('online2_versao').AsString := Online2Versao;
          DefinirDataOpcional(Query, 'ultima_venda',
            UltimaVendaInformada, UltimaVendaEm);
          Query.ParamByName('json').AsString := AJson;
          Query.ParamByName('codigo').AsInteger := CodigoCliente;
          Query.ExecSQL;

          Query.SQL.Text :=
            'UPDATE ' + TABELA_CHAVES + ' SET chave_utilizada_em=NOW() ' +
            'WHERE id=:id AND chave_utilizada_em IS NULL';
          Query.ParamByName('id').AsLargeInt := TokenId;
          Query.ExecSQL;
          if Query.RowsAffected <> 1 then
            raise EDadosClientes.Create(401,
              'A chave temporaria ja foi utilizada.');

          DM.ZConexaoBancR.Commit;
          EmTransacao := False;
        except
          if EmTransacao then
            DM.ZConexaoBancR.Rollback;
          raise;
        end;
      finally
        Query.Free;
      end;
    finally
      TMonitor.Exit(GLockBanco);
    end;
  finally
    Raiz.Free;
    Token := '';
  end;
  Result := JsonSucesso('Dados do cliente recebidos e atualizados.');
end;

class function TDadosClientes.RespostaErro(const AMensagem: string): string;
begin
  Result := JsonErro(AMensagem);
end;

procedure RotaLiberacao(Req: THorseRequest; Res: THorseResponse);
var
  IdClienteLocal: Integer;
begin
  try
    if not TryStrToInt(Trim(Req.Query['idCli']), IdClienteLocal) then
      IdClienteLocal := 0;
    Res.ContentType('application/json; charset=utf-8')
      .Send(TDadosClientes.ConsultarLiberacao(
        Req.Query['cpfcnpj'], IdClienteLocal)).Status(200);
  except
    on E: EDadosClientes do
      Res.ContentType('application/json; charset=utf-8')
        .Send(TDadosClientes.RespostaErro(E.Message)).Status(E.StatusHttp);
    on E: Exception do
      Res.ContentType('application/json; charset=utf-8')
        .Send(TDadosClientes.RespostaErro(
          'Falha interna ao consultar a liberacao.')).Status(500);
  end;
end;

procedure RotaTelemetria(Req: THorseRequest; Res: THorseResponse);
begin
  try
    Res.ContentType('application/json; charset=utf-8')
      .Send(TDadosClientes.Receber(
        Req.Headers['Authorization'], Req.Body(TEncoding.UTF8))).Status(200);
  except
    on E: EDadosClientes do
      Res.ContentType('application/json; charset=utf-8')
        .Send(TDadosClientes.RespostaErro(E.Message)).Status(E.StatusHttp);
    on E: Exception do
      Res.ContentType('application/json; charset=utf-8')
        .Send(TDadosClientes.RespostaErro(
          'Falha interna ao receber os dados do cliente.')).Status(500);
  end;
end;

initialization
  GBancoPreparado := False;
  GLockBanco := TObject.Create;
  THorse.Get('/api/v1/liberacao', RotaLiberacao);
  THorse.Post(ROTA_TELEMETRIA, RotaTelemetria);

finalization
  GLockBanco.Free;

end.
