"""A single dedicated Edge window controlling the real youtube.com video."""
from pathlib import Path
import time
import json
from urllib.parse import urlsplit, parse_qs, urljoin


def validate_url(url):
    p = urlsplit(url)
    if p.scheme != 'https' or p.hostname not in ('www.youtube.com','youtube.com','youtu.be') or p.username:
        raise ValueError('https YouTube video/playlist URL required')
    if p.hostname != 'youtu.be' and p.path not in ('/watch','/playlist'):
        raise ValueError('Use a YouTube watch or playlist URL')
    return url


class YouTubeDirect:
    def __init__(self, root):
        self.root = Path(root)
        self.runtime = self.context = self.page = None
        self.last_recovery = float("-inf")

    def open(self, url):
        validate_url(url)
        if self.page is not None:
            try:self.page.title()  # Pump browser disconnect events before reusing it.
            except Exception:self.page=None
        if self.page is None or self.page.is_closed():
            if self.context:
                try: self.context.close()
                except Exception: pass
                self.context = None
            if self.runtime is None:
                from playwright.sync_api import sync_playwright
                self.runtime = sync_playwright().start()
            self.context = self.runtime.chromium.launch_persistent_context(
                str((self.root/'youtube_profile').resolve()), channel='msedge',
                headless=False, no_viewport=True, chromium_sandbox=True)
            self.page = self.context.pages[0] if self.context.pages else self.context.new_page()
            self.page.set_default_timeout(5000)
            self.page.goto(url, wait_until='domcontentloaded', timeout=25000)
        self.page.bring_to_front()
        focused = False
        try:
            try:from .window_focus import focus_edge
            except ImportError:from window_focus import focus_edge
            focused=focus_edge(self.root/'youtube_profile')
        except Exception:
            pass
        return {'ok':True,'detail':'YouTube window ready' + ('' if focused else ' (click the Edge taskbar icon if Windows kept it behind)'), 'url':self.page.url}

    def playback_error(self):
        """Only explicit player/media errors trigger recovery, not normal buffering."""
        try:
            return self.page.evaluate("""() => {
                const p=document.querySelector('#movie_player');
                const v=p?.querySelector('video.html5-main-video');
                const e=p?.querySelector('.ytp-error');
                const visible=!!e && e.getClientRects().length>0 &&
                    getComputedStyle(e).visibility!=='hidden';
                return {failed:!!v?.error || visible,
                        code:v?.error?.code || null,
                        message:visible ? (e.innerText || '').slice(0,300) : '',
                        video_id:new URL(location.href).searchParams.get('v'),
                        position:v?.currentTime || 0, ready_state:v?.readyState,
                        network_state:v?.networkState,
                        volume:typeof p?.getVolume==='function'?p.getVolume():null,
                        muted:typeof p?.isMuted==='function'?p.isMuted():v?.muted,
                        online:navigator.onLine};
            }""")
        except Exception:
            return {'failed':False}

    def recover_playback(self, error):
        if time.monotonic()-self.last_recovery<30:
            raise RuntimeError('YouTube playback error persists. Recovery is limited to once per 30 seconds; check the browser/network. MEDIA mode remains active.')
        self.last_recovery=time.monotonic()
        # Diagnostic failure must not prevent recovery; do not log keys/cookies.
        try:
            with (self.root/'playback_errors.jsonl').open('a',encoding='utf-8') as log:
                log.write(json.dumps({'time':time.time(),'error':error},ensure_ascii=False)+'\n')
        except OSError:
            pass
        self.page.reload(wait_until='domcontentloaded',timeout=20000)
        # Restore only the same video; never seek a newly selected video or an ad.
        if error.get('video_id'):
            self.page.wait_for_function('''id=>{
                const p=document.querySelector('#movie_player');
                return p && !p.classList.contains('ad-showing') &&
                    p.getVideoData?.().video_id===id && p.getDuration?.()>0;
            }''',arg=error['video_id'],timeout=15000)
            self.page.evaluate('''s=>{
                const p=document.querySelector('#movie_player');
                if(Number.isFinite(s.position) && s.position>0)p.seekTo?.(s.position,true);
                if(Number.isFinite(s.volume))p.setVolume?.(s.volume);
                if(s.muted===true)p.mute?.();
                else if(s.muted===false)p.unMute?.();
            }''',error)

    def execute(self, command):
        if command not in ('PLAY','PAUSE','VOLUME_UP','VOLUME_DOWN','VIDEO_NEXT','VIDEO_PREVIOUS'):
            raise ValueError('Unknown video command')
        if self.page is None or self.page.is_closed():
            raise RuntimeError('The controlled YouTube window was closed. Open MEDIA again.')
        recovered=False
        # Recovery is requested by a new PLAY gesture, never a background loop.
        error=self.playback_error()
        if error.get('failed') and command not in ('PLAY','VIDEO_NEXT','VIDEO_PREVIOUS'):
            raise RuntimeError('YouTube playback error: command not confirmed. Exit swipe mode with OK, then use PLAY to reload and retry.')
        if error.get('failed') and command=='PLAY':
            self.recover_playback(error)
            recovered=True
        try:
            result=self._execute(command)
        except Exception:
            error=self.playback_error() if command=='PLAY' and not recovered else {'failed':False}
            if not error.get('failed'):
                raise
            self.recover_playback(error)
            result=self._execute(command)
            recovered=True
        if recovered:
            result['detail']='YouTube reloaded once; '+result['detail']
        return result

    def _execute(self, command):
        if self.page is None or self.page.is_closed():
            raise RuntimeError('Select MEDIA again to open the controlled YouTube window')
        host=urlsplit(self.page.url).hostname
        if host not in ('www.youtube.com','youtube.com'):
            raise RuntimeError('Complete any YouTube sign-in/consent in the controlled window first')
        video=self.page.locator('#movie_player video.html5-main-video').first
        video.wait_for(state='attached')
        player=self.page.locator('#movie_player')
        if command=='PLAY':
            player.evaluate('(p)=>{if(typeof p.playVideo==="function")p.playVideo();else return p.querySelector("video").play()}')
            self.page.wait_for_function("()=>{const v=document.querySelector('video.html5-main-video');return v&&!v.paused&&!v.ended}",timeout=4000)
            before=video.evaluate('(v)=>v.currentTime')
            self.page.wait_for_function("t=>{const v=document.querySelector('video.html5-main-video');return v&&!v.paused&&v.currentTime>t+0.1}",arg=before,timeout=4000)
        elif command=='PAUSE':
            player.evaluate('(p)=>{if(typeof p.pauseVideo==="function")p.pauseVideo();else p.querySelector("video").pause()}')
            self.page.wait_for_function("()=>document.querySelector('video.html5-main-video')?.paused",timeout=2000)
            before=video.evaluate('(v)=>v.currentTime')
            self.page.wait_for_timeout(500)
            if not video.evaluate('(v)=>v.paused') or abs(video.evaluate('(v)=>v.currentTime')-before)>.1:
                raise RuntimeError('Video time is still advancing; pause not confirmed')
        elif command in ('VOLUME_UP','VOLUME_DOWN'):
            delta=.10 if command=='VOLUME_UP' else -.10
            target=player.evaluate('''(p,d)=>{
                const v=p.querySelector('video.html5-main-video');
                const current=typeof p.getVolume==='function'?p.getVolume()/100:v.volume;
                const target=Math.max(0,Math.min(1,current+d));
                if(typeof p.setVolume==='function')p.setVolume(Math.round(target*100));else v.volume=target;
                if(target>0){if(typeof p.unMute==='function')p.unMute();else v.muted=false;}
                return target;
            }''',delta)
            self.page.wait_for_timeout(200)
            actual=player.evaluate('(p)=>typeof p.getVolume==="function"?p.getVolume()/100:p.querySelector("video").volume')
            if abs(actual-target)>.011 or (target>0 and video.evaluate('(v)=>v.muted')):
                raise RuntimeError('YouTube player volume/mute state did not match the request')
        elif command in ('VIDEO_NEXT','VIDEO_PREVIOUS'):
            direction=1 if command=='VIDEO_NEXT' else -1
            query=parse_qs(urlsplit(self.page.url).query)
            if not query.get('list'):
                raise RuntimeError('Open a YouTube playlist URL first (list= is required).')
            # Use actual adjacent playlist entries, never browser history or recommendations.
            panel=self.page.locator('ytd-playlist-panel-renderer').first
            panel.wait_for(state='attached',timeout=5000)
            target=panel.evaluate("""(p,step)=>{
                const items=Array.from(p.querySelectorAll('ytd-playlist-panel-video-renderer'));
                const current=items.findIndex(e=>e.hasAttribute('selected'));
                if(current<0)return {error:'Current playlist entry not found'};
                const next=items[current+step];
                if(!next)return {error:step<0?'Already at first playlist entry':'Already at last loaded playlist entry'};
                const href=next.querySelector('a#wc-endpoint')?.href;
                return href?{url:href}:{error:'Adjacent playlist video is unavailable'};
            }""",direction)
            if target.get('error'):raise RuntimeError(target['error'])
            url=validate_url(target['url'])
            if parse_qs(urlsplit(url).query).get('list')!=query.get('list'):
                raise RuntimeError('Adjacent video does not belong to the current playlist')
            self.page.goto(url,wait_until='domcontentloaded',timeout=20000)
            result=self.execute('PLAY')
            result['detail']=('Next' if direction>0 else 'Previous')+' playlist video opened; '+result['detail']
            return result
        else:
            raise ValueError('Unknown video command')
        info=player.evaluate('''(p)=>{const v=p.querySelector('video.html5-main-video');
            return {paused:v.paused,time:Math.round(v.currentTime*10)/10,
                volume:Math.round(typeof p.getVolume==='function'?p.getVolume():v.volume*100),
                media_volume:Math.round(v.volume*100)};}''')
        return {'ok':True,'detail':f'{command} verified on youtube.com: {info}', 'url':self.page.url, **info}

    def close(self):
        try:
            if self.context: self.context.close()
        finally:
            if self.runtime: self.runtime.stop()
