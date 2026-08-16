program G2Services;

uses
  Vcl.Forms,
  uprinc in 'uprinc.pas' {frmprinc},
  Horse.Callback in 'horse-master\src\Horse.Callback.pas',
  Horse.Commons in 'horse-master\src\Horse.Commons.pas',
  Horse.Constants in 'horse-master\src\Horse.Constants.pas',
  Horse.Core.Files in 'horse-master\src\Horse.Core.Files.pas',
  Horse.Core.Group.Contract in 'horse-master\src\Horse.Core.Group.Contract.pas',
  Horse.Core.Group in 'horse-master\src\Horse.Core.Group.pas',
  Horse.Core.Param.Config in 'horse-master\src\Horse.Core.Param.Config.pas',
  Horse.Core.Param.Field.Brackets in 'horse-master\src\Horse.Core.Param.Field.Brackets.pas',
  Horse.Core.Param.Field in 'horse-master\src\Horse.Core.Param.Field.pas',
  Horse.Core.Param.Header in 'horse-master\src\Horse.Core.Param.Header.pas',
  Horse.Core.Param in 'horse-master\src\Horse.Core.Param.pas',
  Horse.Core in 'horse-master\src\Horse.Core.pas',
  Horse.Core.Route.Contract in 'horse-master\src\Horse.Core.Route.Contract.pas',
  Horse.Core.Route in 'horse-master\src\Horse.Core.Route.pas',
  Horse.Core.RouterTree.NextCaller in 'horse-master\src\Horse.Core.RouterTree.NextCaller.pas',
  Horse.Core.RouterTree in 'horse-master\src\Horse.Core.RouterTree.pas',
  Horse.EnvironmentVariables in 'horse-master\src\Horse.EnvironmentVariables.pas',
  Horse.Exception.Interrupted in 'horse-master\src\Horse.Exception.Interrupted.pas',
  Horse.Exception in 'horse-master\src\Horse.Exception.pas',
  Horse.Mime in 'horse-master\src\Horse.Mime.pas',
  Horse in 'horse-master\src\Horse.pas',
  Horse.Proc in 'horse-master\src\Horse.Proc.pas',
  Horse.Provider.Abstract in 'horse-master\src\Horse.Provider.Abstract.pas',
  Horse.Provider.Apache in 'horse-master\src\Horse.Provider.Apache.pas',
  Horse.Provider.CGI in 'horse-master\src\Horse.Provider.CGI.pas',
  Horse.Provider.Console in 'horse-master\src\Horse.Provider.Console.pas',
  Horse.Provider.Daemon in 'horse-master\src\Horse.Provider.Daemon.pas',
  Horse.Provider.FPC.Apache in 'horse-master\src\Horse.Provider.FPC.Apache.pas',
  Horse.Provider.FPC.CGI in 'horse-master\src\Horse.Provider.FPC.CGI.pas',
  Horse.Provider.FPC.Daemon in 'horse-master\src\Horse.Provider.FPC.Daemon.pas',
  Horse.Provider.FPC.FastCGI in 'horse-master\src\Horse.Provider.FPC.FastCGI.pas',
  Horse.Provider.FPC.HTTPApplication in 'horse-master\src\Horse.Provider.FPC.HTTPApplication.pas',
  Horse.Provider.FPC.LCL in 'horse-master\src\Horse.Provider.FPC.LCL.pas',
  Horse.Provider.IOHandleSSL.Contract in 'horse-master\src\Horse.Provider.IOHandleSSL.Contract.pas',
  Horse.Provider.IOHandleSSL in 'horse-master\src\Horse.Provider.IOHandleSSL.pas',
  Horse.Provider.ISAPI in 'horse-master\src\Horse.Provider.ISAPI.pas',
  Horse.Provider.VCL in 'horse-master\src\Horse.Provider.VCL.pas',
  Horse.Request in 'horse-master\src\Horse.Request.pas',
  Horse.Response in 'horse-master\src\Horse.Response.pas',
  Horse.Rtti.Helper in 'horse-master\src\Horse.Rtti.Helper.pas',
  Horse.Rtti in 'horse-master\src\Horse.Rtti.pas',
  Horse.Session in 'horse-master\src\Horse.Session.pas',
  Horse.WebModule in 'horse-master\src\Horse.WebModule.pas' {HorseWebModule: TWebModule},
  ThirdParty.Posix.Syslog in 'horse-master\src\ThirdParty.Posix.Syslog.pas',
  Web.WebConst in 'horse-master\src\Web.WebConst.pas',
  uDM in 'uDM.pas' {DM: TDataModule},
  uDadosClientes in 'uDadosClientes.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(Tfrmprinc, frmprinc);
  Application.CreateForm(TDM, DM);
  Application.Run;
end.
