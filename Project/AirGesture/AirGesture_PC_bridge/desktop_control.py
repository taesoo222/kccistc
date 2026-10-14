"""Serialize browser/COM access on one owning thread."""
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
try:
    from .youtube_direct import YouTubeDirect
    from . import powerpoint_control
except ImportError:
    from youtube_direct import YouTubeDirect
    import powerpoint_control


class DesktopControl:
    def __init__(self,root):
        self.root=Path(root)
        self.youtube=YouTubeDirect(root)
        self.mode='MAIN'
        self.pool=ThreadPoolExecutor(max_workers=1,thread_name_prefix='desktop')

    def execute(self,command):
        return self.pool.submit(self._execute,command).result()

    def _execute(self,command):
        if command=='MODE_MOUSE':
            self.mode='MOUSE'
            return {'ok':True,'detail':'MOUSE: F8 toggles pointer control'}
        if command=='MODE_MAIN':
            self.mode='MAIN'
            return {'ok':True,'detail':'MAIN: gesture commands stopped'}
        if command=='MODE_MEDIA':
            config=json.loads((self.root/'desktop_config.json').read_text(encoding='utf-8-sig'))
            result=self.youtube.open(config['youtube_url'])
            self.mode='MEDIA'
            return result
        if command=='MODE_PPT':
            result=powerpoint_control.manage('recent')
            self.mode='PPT'
            return result
        if command in ('NEXT','PREVIOUS'):
            if self.mode!='PPT':raise RuntimeError('Select PPT mode first')
            return powerpoint_control.execute(command)
        if self.mode!='MEDIA':raise RuntimeError('Select MEDIA mode first')
        return self.youtube.execute(command)

    def close(self):
        self.pool.submit(self.youtube.close).result()
        self.pool.shutdown()
