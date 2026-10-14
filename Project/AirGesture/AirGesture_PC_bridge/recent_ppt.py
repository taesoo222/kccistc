"""Resolve existing local PowerPoint files from Windows/Office recent metadata."""
from pathlib import Path
import os
import re


def mru_entry(value):
    if not isinstance(value,str) or '*' not in value: return None
    metadata,path=value.split('*',1)
    stamp=re.search(r'\[T([0-9A-Fa-f]+)\]',metadata)
    if not stamp: return None
    return ((int(stamp.group(1),16)-116444736000000000)/10000000,path)


def recent_presentation():
    import winreg
    import win32com.client
    candidates=[]
    def visit(path,depth=0):
        if depth>4:return
        try:
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER,path) as key:
                if path.endswith('File MRU'):
                    for i in range(winreg.QueryInfoKey(key)[1]):
                        value=winreg.EnumValue(key,i)[1]
                        item=mru_entry(value)
                        if item:candidates.append(item)
                for i in range(winreg.QueryInfoKey(key)[0]):
                    visit(path+'\\'+winreg.EnumKey(key,i),depth+1)
        except OSError:pass
    for version in ('16.0','15.0'):
        visit('Software\\Microsoft\\Office\\'+version+'\\PowerPoint')
    shell=win32com.client.Dispatch('WScript.Shell')
    for folder in (Path(os.environ['APPDATA'])/'Microsoft/Windows/Recent',Path(os.environ['APPDATA'])/'Microsoft/Office/Recent'):
        for link in folder.glob('*.lnk'):
            try:
                target=shell.CreateShortcut(str(link)).TargetPath
                if Path(target).suffix.lower() in ('.pptx','.ppt'):
                    candidates.append((link.stat().st_mtime,target))
            except Exception:pass
    for _,value in sorted(candidates,reverse=True):
        path=Path(value)
        if path.suffix.lower() in ('.pptx','.ppt') and path.is_file():return str(path)
    raise RuntimeError('No existing local recent PPT found. Open your PPT once in PowerPoint, then select PPT mode again.')
