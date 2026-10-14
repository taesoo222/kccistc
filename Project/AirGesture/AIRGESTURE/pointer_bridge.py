"""Latest-state mouse channel, separate from slow media commands."""
import json
import threading
import uuid
import time
from urllib.request import Request, build_opener, ProxyHandler

class PointerBridge:
    def __init__(self,url,token):
        self.url=url.rstrip('/')+'/pointer'
        self.token=token
        self.session=uuid.uuid4().hex
        self.condition=threading.Condition()
        self.pending=[]
        self.previous=None
        self.sequence=0
        self.stopped=False
        self.status='WAITING'
        self.worker=threading.Thread(target=self._run,daemon=True)
        self.worker.start()
    def publish(self,state):
        with self.condition:
            self.sequence+=1
            data=dict(state,session=self.session,sequence=self.sequence, queued_at=time.monotonic())
            edge=self.previous is None or any(state[k]!=self.previous[k] for k in ('active','left','right_clicks','wheel'))
            self.previous=dict(state)
            if len(self.pending)>=12:
                self.pending.clear()
                data.update(active=False,left=False)
            if not edge and self.pending and not self.pending[-1][1]: self.pending[-1]=(data,False)
            else: self.pending.append((data,edge))
            self.condition.notify()
    def _run(self):
        opener=build_opener(ProxyHandler({}))
        while True:
            with self.condition:
                self.condition.wait_for(lambda:self.pending or self.stopped)
                if self.stopped and not self.pending: return
                data,_=self.pending.pop(0)
            created=data.pop('queued_at')
            if time.monotonic()-created>.15:
                data.update(active=False,left=False)
            try:
                req=Request(self.url,json.dumps(data).encode(),headers={'Authorization':'Bearer '+self.token,'Content-Type':'application/json'})
                with opener.open(req,timeout=.2) as response: response.read()
                self.status='CONNECTED'
            except Exception as error:
                self.status=type(error).__name__
                with self.condition: self.pending.clear()
    def close(self):
        with self.condition:
            self.pending.clear()
        self.publish(dict(active=False,left=False,x=None,y=None,right_clicks=0,wheel=0))
        with self.condition:
            self.stopped=True
            self.condition.notify()
        self.worker.join(timeout=.5)
