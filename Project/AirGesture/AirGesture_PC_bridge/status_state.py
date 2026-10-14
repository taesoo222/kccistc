"""Small, thread-safe recognition/result snapshot for the desktop HUD."""
import math
import threading
import time
import base64
import binascii


class StatusState:
    def __init__(self):
        self.lock=threading.Lock()
        self.recognition={}
        self.received=None
        self.result={}
        self.finished_at=None
        self.pending=''
        self.visible=True

    def update(self,data):
        if data.get('mode') not in ('MAIN','MEDIA','PPT','MOUSE'):
            raise ValueError('Invalid recognition mode')
        clean={'mode':data['mode']}
        for key in ('gesture','selector','bridge_status','swipe_status','last_command','last_swipe'):
            clean[key]=str(data.get(key,''))[:70]
        for key in ('hand','enabled','volume_lock','release_gate','swipe_active'):
            clean[key]=data.get(key) is True
        progress=data.get('progress',0)
        if not isinstance(progress,(float,int)) or not math.isfinite(progress):
            raise ValueError('Invalid progress')
        clean['progress']=max(0,min(1,progress))
        frame=data.get('frame','')
        if not isinstance(frame,str) or len(frame)>130000:raise ValueError('Invalid preview size')
        if frame:
            try:raw=base64.b64decode(frame,validate=True)
            except (ValueError,binascii.Error):raise ValueError('Invalid preview encoding')
            if not raw.startswith(b'\xff\xd8') or not raw.endswith(b'\xff\xd9'):
                raise ValueError('Expected JPEG preview')
        clean['frame']=frame
        port=data.get('stream_port',8767)
        if type(port) is not int or not 1<=port<=65535: raise ValueError('Invalid stream port')
        clean['stream_port']=port
        clean['preview_transport']='mjpeg' if data.get('preview_transport')=='mjpeg' else 'legacy'
        clean['stream_host']=str(data.get('stream_host',''))[:64]
        with self.lock:
            self.recognition=clean;self.received=time.monotonic()

    def begin(self,command):
        with self.lock:self.pending=command

    def finish(self,command,result):
        with self.lock:
            self.pending='';self.result={**result,'command':command}
            self.finished_at=time.monotonic()

    def snapshot(self):
        with self.lock:
            age=None if self.received is None else time.monotonic()-self.received
            return {'recognition':dict(self.recognition),'age':age,'result':dict(self.result),
                    'pending':self.pending,'visible':self.visible,
                    'result_age':None if self.finished_at is None else time.monotonic()-self.finished_at}


def swipe_display(data):
    r=data.get('recognition',{});age=data.get('age')
    if age is None or age>=2.5:return '연결 대기\nPi 인식 프로그램을 확인하세요', '#94a3b8'
    if str(r.get('swipe_status','')).startswith(('SWIPE EXIT:', 'EXIT & NEXT:')):
        return '스와이프 해제 · OFF\n잠시 대기 후 손동작을 풀어 주세요', '#fbbf24'
    if r.get('swipe_active'):
        if not r.get('hand'):return '스와이프 대기 · ON\n손을 카메라에 보여 주세요', '#fbbf24'
        if r.get('release_gate'):return '스와이프 대기 · ON\n모드 선택 자세를 풀어 주세요', '#fbbf24'
        if not r.get('enabled'):return '스와이프 대기 · ON\n인식 일시 정지', '#fbbf24'
        if 'RETURN TO CENTER' in r.get('swipe_status',''):return '스와이프 대기 · ON\n손을 원래 위치로 돌려 주세요', '#fbbf24'
        return '스와이프 대기 · ON\n좌우로 이동하면 다음 / 이전', '#67e8f9'
    if r.get('volume_lock') or (r.get('hand') and r.get('gesture')=='VOLUME_READY'):
        return '음량 조절 대기\n손을 회전하면 음량 조절 · 스와이프 OFF', '#67e8f9'
    if r.get('release_gate'):hint='모드 선택 자세를 풀어 주세요'
    elif not r.get('hand'):hint='손을 카메라에 보여 주세요'
    elif r.get('mode') in ('MEDIA','PPT'):hint='OK 손동작으로 스와이프 시작'
    else:hint='손동작으로 모드를 선택하세요'
    return '일반 제어 · 스와이프 OFF\n'+hint, '#94a3b8'


def overlay_lines(data):
    r=data.get('recognition',{});result=data.get('result',{})
    age=data.get('age');online=age is not None and age<2.5
    heading=r.get('mode','MAIN') if online else '연결 대기'
    name={'OPEN_PALM':'보자기','FIST':'주먹','VOLUME_READY':'음량 조절 자세',
          'OK':'OK 사인','SWIPE_EXIT':'스와이프 해제 자세','UNKNOWN':'판정 중','NONE':'손 없음'}
    gesture=r.get('gesture','NONE') if online else 'NONE'
    pose='동작  '+name.get(gesture,gesture)
    gate,_=swipe_display(data)
    pending=data.get('pending');command=result.get('command','')
    names={'VIDEO_NEXT':'다음 영상','VIDEO_PREVIOUS':'이전 영상','PLAY':'재생','PAUSE':'일시정지',
           'VOLUME_UP':'음량 올리기','VOLUME_DOWN':'음량 내리기','MODE_MEDIA':'MEDIA 진입','MODE_PPT':'PPT 진입',
           'MODE_MAIN':'MAIN 복귀','NEXT':'다음 슬라이드','PREVIOUS':'이전 슬라이드'}
    result_age=data.get('result_age')
    fresh=result_age is None or result_age<6
    if pending:outcome=names.get(pending,pending)+' 처리 중'
    elif command and fresh:
        outcome=names.get(command,command)+(' 완료' if result.get('ok') else ' 실패')
        if 'volume' in result:outcome+=f" · 음량 {result['volume']}"
        if not result.get('ok'):
            detail=str(result.get('detail',''))
            if 'Select MEDIA' in detail:outcome+=' · MAIN → MEDIA 재진입'
            else:outcome+=' · PC 터미널 확인'
    else:outcome='명령 대기' if online else 'Pi 신호 대기'
    return heading,pose,gate,outcome
