"""Pure gesture-to-pointer state; no OS side effects."""
import math

class AirMouse:
    def __init__(self):
        self.position=None
        self.last_time=None
        self.left=self.right=self.armed=False
        self.open_since=self.scroll_y=None
        self.scroll_remainder=0.0
        self.right_clicks=self.wheel=0
    def update(self,lm,fingers,enabled,now,aspect=0.75):
        gap=self.last_time is not None and now-self.last_time>0.25
        dt=min(.1,max(.001,now-self.last_time)) if self.last_time is not None else 1/30
        self.last_time=now
        if not enabled or lm is None or gap:
            self.left=self.right=self.armed=False
            self.open_since=self.scroll_y=self.position=None
            self.scroll_remainder=0
            return self.snapshot(False)
        distance=lambda a,b:math.hypot(lm[a].x-lm[b].x,(lm[a].y-lm[b].y)*aspect)
        scale=max(distance(5,17),.025)
        ld,rd=distance(4,8)/scale,distance(4,12)/scale
        if not self.armed:
            if min(ld,rd)>.48:
                if self.open_since is None: self.open_since=now
                self.armed=now-self.open_since>=.18
            else: self.open_since=None
            return self.snapshot(False)
        self.left=ld<(.48 if self.left else .30)
        right=not self.left and rd<(.48 if self.right else .30)
        if right and not self.right: self.right_clicks+=1
        self.right=right
        s=fingers['states']
        scrolling=s['index'] and s['middle'] and not s['ring'] and not s['pinky'] and not self.left and not right
        if scrolling:
            y=(lm[8].y+lm[12].y)/2
            if self.scroll_y is not None:
                self.scroll_remainder+=(self.scroll_y-y)*18
                steps=math.trunc(self.scroll_remainder)
                self.wheel+=steps
                self.scroll_remainder-=steps
            self.scroll_y=y
        else:
            self.scroll_y=None
            self.scroll_remainder=0
            if s['index'] or self.left:
                x=min(1,max(0,(lm[8].x-.12)/.76))
                y=min(1,max(0,(lm[8].y-.12)/.76))
                if self.position is None: self.position=(x,y)
                else:
                    speed=math.hypot(x-self.position[0],y-self.position[1])
                    alpha=1-math.exp(-dt*(12+speed*65))
                    self.position=tuple(a+alpha*(b-a) for a,b in zip(self.position,(x,y)))
        return self.snapshot(True)
    def snapshot(self,active):
        return dict(active=active,x=self.position[0] if self.position else None,
                    y=self.position[1] if self.position else None,left=self.left,
                    right_clicks=self.right_clicks,wheel=self.wheel)
