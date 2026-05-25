object frmprinc: Tfrmprinc
  Left = 0
  Top = 0
  BorderStyle = bsSingle
  Caption = 'Servidor HORSE'
  ClientHeight = 214
  ClientWidth = 762
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  Position = poDesktopCenter
  OnActivate = FormActivate
  OnCreate = FormCreate
  DesignSize = (
    762
    214)
  PixelsPerInch = 96
  TextHeight = 13
  object fundo: TShape
    Left = 4
    Top = 29
    Width = 65
    Height = 65
    Brush.Color = clCream
  end
  object btfechar: TSpeedButton
    Left = 591
    Top = 154
    Width = 160
    Height = 49
    Anchors = [akRight, akBottom]
    Caption = 'Fechar servidor'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -16
    Font.Name = 'Tahoma'
    Font.Style = [fsBold]
    ParentFont = False
    OnClick = btfecharClick
    ExplicitLeft = 584
    ExplicitTop = 266
  end
  object pntitulo: TPanel
    Left = 15
    Top = 12
    Width = 736
    Height = 65
    Anchors = [akLeft, akTop, akRight]
    Caption = 'Servidor HORSE'
    Color = clHighlight
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindow
    Font.Height = -40
    Font.Name = 'Tahoma'
    Font.Style = [fsBold]
    ParentBackground = False
    ParentFont = False
    TabOrder = 0
  end
  object pnconfig: TPanel
    Left = 15
    Top = 83
    Width = 736
    Height = 45
    Anchors = [akLeft, akTop, akRight]
    Color = clMoneyGreen
    ParentBackground = False
    TabOrder = 1
    DesignSize = (
      736
      45)
    object Label1: TLabel
      Left = 13
      Top = 13
      Width = 37
      Height = 19
      Caption = 'Porta'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -16
      Font.Name = 'Tahoma'
      Font.Style = []
      ParentFont = False
    end
    object btativa_desativa: TSpeedButton
      Left = 149
      Top = 7
      Width = 76
      Height = 33
      Caption = 'Ativar'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -13
      Font.Name = 'Tahoma'
      Font.Style = []
      ParentFont = False
      OnClick = btativa_desativaClick
    end
    object lbstatus: TLabel
      Left = 260
      Top = 14
      Width = 503
      Height = 19
      Anchors = [akLeft, akTop, akRight]
      AutoSize = False
      Caption = '* * *'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -13
      Font.Name = 'Tahoma'
      Font.Style = []
      ParentFont = False
      ExplicitWidth = 580
    end
    object edtporta: TMaskEdit
      Left = 56
      Top = 10
      Width = 90
      Height = 27
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -16
      Font.Name = 'Tahoma'
      Font.Style = []
      ParentFont = False
      TabOrder = 0
      Text = '19036'
    end
  end
  object pnrodape: TPanel
    Left = 8
    Top = 154
    Width = 577
    Height = 49
    Anchors = [akLeft, akRight, akBottom]
    Color = clTeal
    ParentBackground = False
    TabOrder = 2
    DesignSize = (
      577
      49)
    object Label2: TLabel
      Left = 347
      Top = 14
      Width = 79
      Height = 19
      Anchors = [akTop, akRight]
      Caption = 'Conex'#245'es'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWhite
      Font.Height = -16
      Font.Name = 'Tahoma'
      Font.Style = [fsBold]
      ParentFont = False
      ExplicitLeft = 340
    end
    object edtconexoes: TMaskEdit
      Left = 432
      Top = 11
      Width = 131
      Height = 27
      Alignment = taRightJustify
      Anchors = [akTop, akRight]
      Enabled = False
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -16
      Font.Name = 'Tahoma'
      Font.Style = []
      ParentFont = False
      TabOrder = 0
      Text = ''
    end
  end
  object Timer: TTimer
    OnTimer = TimerTimer
    Left = 28
    Top = 19
  end
end
