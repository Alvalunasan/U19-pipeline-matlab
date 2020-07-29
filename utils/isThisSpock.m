function isSpock = isThisSpock

if (~isempty(strfind(pwd,'smb'))            || ...
    ~isempty(strfind(pwd,'usr/people'))     || ...
    ~isempty(strfind(pwd,'mnt'))            || ...
    ~isempty(strfind(pwd,'jukebox')))          ...
    && ~ispc
    
  isSpock = true;
  
else
  
  isSpock = false;
  
end

% (isempty(strfind(pwd,'/Users/lucas')) && isempty(strfind(pwd,'/Volumes'))) || ...
%     (isempty(strfind(pwd,'/Users/lpinto')))) ...