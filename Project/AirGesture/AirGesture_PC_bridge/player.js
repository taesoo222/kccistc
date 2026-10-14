const token=document.querySelector('meta[name="bridge-token"]').content;
const statusBox=document.getElementById('status');
let pending=false,signature='';
async function request(path,data){
 const r=await fetch(path,{method:data?'POST':'GET',cache:'no-store',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},...(data?{body:JSON.stringify(data)}:{})});
 const result=await r.json();if(!r.ok)throw Error(result.detail||r.status);return result;
}
document.querySelectorAll('[data-command]').forEach(button=>button.onclick=async()=>{
 if(pending)return;pending=true;
 document.querySelectorAll('button').forEach(b=>b.disabled=true);
 statusBox.textContent='처리 중… 앱을 처음 열 때는 잠시 기다려 주세요.';
 try{const r=await request('/api/command',{id:crypto.randomUUID(),command:button.dataset.command});statusBox.textContent=r.detail;}
 catch(e){statusBox.textContent='실행 실패: '+e.message;}
 finally{pending=false;document.querySelectorAll('button').forEach(b=>b.disabled=false);}
});
async function poll(){
 try{const r=await request('/api/poll?client=dashboard&ready=0');const next=JSON.stringify(r.last_result);
 if(!pending&&next!==signature){statusBox.textContent=r.last_result.detail;signature=next;}}
 catch(e){if(!pending)statusBox.textContent='PC 연결 실패: '+e.message;}
 finally{setTimeout(poll,700);}
}poll();
for(const [id,visible] of [['overlay-show',true],['overlay-hide',false]]){
 document.getElementById(id).onclick=async()=>{
  try{await request('/api/overlay',{visible});statusBox.textContent=visible?'오버레이 표시':'오버레이 숨김';}
  catch(e){statusBox.textContent=e.message;}
 };
}
