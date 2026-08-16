object DM: TDM
  OldCreateOrder = False
  Height = 609
  Width = 807
  object ZConexaoBancR: TZConnection
    ControlsCodePage = cCP_UTF16
    Catalog = ''
    Properties.Strings = (
      'RawStringEncoding=DB_CP')
    DisableSavepoints = False
    HostName = '192.168.10.99'
    Port = 3307
    Database = 'bancr'
    User = 'g2user'
    Password = 'ASdf963a'
    Protocol = 'mysql'
    Left = 80
    Top = 64
  end
  object ZQApp: TZQuery
    Connection = ZConexaoBancR
    Params = <>
    Left = 80
    Top = 128
  end
end
