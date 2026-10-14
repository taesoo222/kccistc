"""One capture worker, latest frame only: no inference-induced camera backlog."""
import threading
import cv2

class Camera:
    def __init__(self, index=0, width=640, height=480, fps=30):
        self.cap = cv2.VideoCapture(index)
        if not self.cap.isOpened():
            self.cap.release()
            raise RuntimeError(f'Cannot open camera: {index}')
        for prop, value in ((cv2.CAP_PROP_FRAME_WIDTH,width),(cv2.CAP_PROP_FRAME_HEIGHT,height),
                            (cv2.CAP_PROP_FPS,fps),(cv2.CAP_PROP_BUFFERSIZE,1)):
            self.cap.set(prop,value)
        self.condition=threading.Condition()
        self.stopped=threading.Event()
        self.frame=None
        self.sequence=0
        self.worker=threading.Thread(target=self._capture,daemon=True)
        self.worker.start()

    def _capture(self):
        try:
            while not self.stopped.is_set():
                ok,frame=self.cap.read()
                if not ok: break
                with self.condition:
                    self.frame=frame
                    self.sequence+=1
                    self.condition.notify_all()
        finally:
            self.stopped.set()
            with self.condition: self.condition.notify_all()

    def snapshot(self,after=0,timeout=2):
        with self.condition:
            self.condition.wait_for(lambda:self.sequence>after or self.stopped.is_set(),timeout)
            if self.stopped.is_set() or self.sequence<=after: return self.sequence,None
            return self.sequence,self.frame.copy()

    def read(self):
        return self.snapshot()[1]

    def release(self):
        self.stopped.set()
        with self.condition: self.condition.notify_all()
        self.worker.join(timeout=2)
        self.cap.release()
