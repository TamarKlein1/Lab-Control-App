function SendGmail(LoginMail, Password, ToWhomMail, Subject, Content, attachments)
% SendGmail - Send an email via a Gmail SMTP account.
%   LoginMail = sending Gmail address
%   Password  = Gmail App Password (2FA accounts cannot use the normal password)
%   ToWhomMail = recipient email address
%   Subject/Content = message subject/body
%   attachments (optional) = file path or cell array of file paths

setpref('Internet', 'SMTP_Server', 'smtp.gmail.com');

setpref('Internet', 'E_mail', LoginMail);
setpref('Internet', 'SMTP_Username', LoginMail);
setpref('Internet', 'SMTP_Password', Password);
props = java.lang.System.getProperties;
props.setProperty('mail.smtp.auth', 'true');
props.setProperty('mail.smtp.socketFactory.class', 'javax.net.ssl.SSLSocketFactory');
props.setProperty('mail.smtp.socketFactory.port', '465');

if exist('attachments', 'var')
    sendmail(ToWhomMail, Subject, Content, attachments)
else
    sendmail(ToWhomMail, Subject, Content)
end
end
