"""OK sign requires thumb/index pinch and at least two other extended fingers."""
import math

def ok_pose_details(fingers, lm, aspect_ratio=.75):
    if fingers is None or lm is None:
        return {'matched':False,'pinch_ratio':None,'extended':0}
    extended=sum(bool(fingers['states'][n]) for n in ('middle','ring','pinky'))
    def distance(a,b):
        return math.hypot(lm[a].x-lm[b].x,(lm[a].y-lm[b].y)*aspect_ratio)
    width=distance(5,17)
    pinch=distance(4,8)
    valid=math.isfinite(width) and math.isfinite(pinch) and width>=.025
    ratio=pinch/width if valid else None
    return {'matched':valid and extended>=2 and ratio<=.35,'pinch_ratio':ratio,'extended':extended}


def is_ok_pose(fingers,lm,aspect_ratio=.75):
    return ok_pose_details(fingers,lm,aspect_ratio)['matched']
