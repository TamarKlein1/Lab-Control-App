function SendGmailPPMS(ToWhomMail, Subject, Content, attachments)
% SendGmailPPMS - Send a PPMS notification email from the lab's Gmail account.
% Fill in the sending account's address and Gmail App Password below
% (2FA-enabled Gmail accounts require an App Password, not the login password).
%
% SECURITY NOTE: this file is tracked in git. Do not commit a real
% password here - replace 'TEMP'/'PSWRD' with the real credentials only
% in a local, untracked copy (or load them from an environment variable /
% untracked config file instead of hardcoding).

if exist('attachments', 'var')
    SendGmail('TEMP', 'PSWRD', ToWhomMail, Subject, Content, attachments); % Add AppPassword as MATLAB doesn't support 2FA on 2021-10-31
else
    SendGmail('TEMP', 'PSWRD', ToWhomMail, Subject, Content); % Add AppPassword as MATLAB doesn't support 2FA on 2021-10-31
end
end
