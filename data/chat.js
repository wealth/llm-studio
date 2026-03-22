var KATEX_OPTS={
  delimiters:[
    {left:"$$",right:"$$",display:true},
    {left:"\\[",right:"\\]",display:true},
    {left:"$",right:"$",display:false},
    {left:"\\(",right:"\\)",display:false}
  ],
  ignoredTags:["script","noscript","style","textarea","pre","code","annotation","annotation-xml"],
  throwOnError:false,output:"html"
};
function katexEl(el){
  if(typeof renderMathInElement!=='undefined'){
    try{renderMathInElement(el,KATEX_OPTS);}catch(e){console.error(e);}
  }
}
function llmRenderAll(){
  if(typeof hlElement!=='undefined')hlElement(document.body);
  katexEl(document.body);
}
function scrollBottom(){if (window.scrollY != 0) window.scrollTo(0,document.body.scrollHeight);}
function escHtml(s){return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');}
function llmClear(){document.getElementById('chat').innerHTML='';}

/* ── Round tracking ────────────────────────────────────────────────────
   Each streaming message can have multiple agentic rounds:
     round 1: [think?] [tool-calls?] [resp?]
     round 2: [think?] [tool-calls?] [resp?]
     ...
   All elements use IDs: asst-{id}-r{n}-think, asst-{id}-r{n}-tools,
   asst-{id}-r{n}-resp. msgRounds[id] tracks the current round number.  */
var msgRounds={};
function _rid(id){return id+'-r'+(msgRounds[id]||1);}
function _roundHtml(id,r){
  var rid=id+'-r'+r;
  return '<details class="think" id="asst-'+rid+'-think" hidden>'+
           '<summary>Thinking\u2026</summary>'+
           '<div class="tk" id="asst-'+rid+'-think-body"></div>'+
         '</details>'+
         '<div class="tool-calls" id="asst-'+rid+'-tools"></div>'+
         '<div class="asst-content" id="asst-'+rid+'-resp">'+
           '<span class="dot"></span><span class="dot"></span><span class="dot"></span>'+
         '</div>';
}

/* ── User messages ─────────────────────────────────────────────────── */
function llmCopyUser(idx){
  var row=document.getElementById('u-'+idx);
  if(!row)return;
  var bubble=row.querySelector('.user-bubble');
  navigator.clipboard.writeText(bubble?bubble.dataset.raw||bubble.textContent:row.textContent).catch(function(){});
}
function llmCopyRow(id){
  var row=document.getElementById('asst-'+id);
  if(!row)return;
  var raw=row.dataset.raw;
  if(!raw){var el=row.querySelector('[data-raw]');if(el)raw=el.dataset.raw||el.textContent;}
  if(raw)navigator.clipboard.writeText(raw).catch(function(){});
}
function llmCopyChat(){
  var chat=document.getElementById('chat');
  if(!chat)return false;
  navigator.clipboard.writeText(chat.outerHTML).catch(function(){});
  return true;
}
function llmDeleteExchange(idx){
  var ur=document.getElementById('u-'+idx);
  var ar=document.getElementById('asst-m'+idx);
  if(ur)ur.remove();
  if(ar)ar.remove();
  if(window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.llm)
    window.webkit.messageHandlers.llm.postMessage(JSON.stringify({action:'delete',index:idx}));
}
function llmAddUser(idx,text,attsJson){
  var d=document.createElement('div');
  d.className='user-row';d.id='u-'+idx;
  var col=document.createElement('div');
  col.className='user-col';
  if(attsJson){try{
    var atts=JSON.parse(attsJson);
    for(var i=0;i<atts.length;i++){
      var a=atts[i];
      if(a.type==='image'){
        var img=document.createElement('img');
        img.className='att-img';img.src=a.src;img.alt=escHtml(a.filename);
        col.appendChild(img);
      }else{
        var chip=document.createElement('div');
        chip.className='att-chip';
        chip.textContent='\uD83D\uDCC4 '+a.filename;
        col.appendChild(chip);
      }
    }
  }catch(e){}}
  if(text){
    var b=document.createElement('div');
    b.className='user-bubble';
    b.innerHTML=text;
    katexEl(b);
    col.appendChild(b);
  }
  var acts=document.createElement('div');
  acts.className='user-actions';
  acts.innerHTML='<button onclick="llmCopyUser('+idx+')">Copy</button>'+
                 '<button onclick="llmDeleteExchange('+idx+')">Delete</button>';
  col.appendChild(acts);
  d.appendChild(col);
  document.getElementById('chat').appendChild(d);
  scrollBottom();
}

/* ── Assistant message lifecycle ───────────────────────────────────── */
function llmStartAssistant(id,model){
  var d=document.createElement('div');
  d.className='asst-row';d.id='asst-'+id;
  d.innerHTML=
    '<div class="asst-name">'+escHtml(model)+'</div>'+
    '<div class="rounds" id="asst-'+id+'-rounds">'+
      _roundHtml(id,1)+
    '</div>'+
    '<div class="asst-stats" id="asst-'+id+'-stats"></div>'+
    '<div class="asst-actions" id="asst-'+id+'-acts" hidden></div>';
  msgRounds[id]=1;
  document.getElementById('chat').appendChild(d);
  scrollBottom();
}
function llmNewRound(id){
  /* Collapse current round's think, clear loading dots, append fresh round. */
  var curRid=_rid(id);
  var curThink=document.getElementById('asst-'+curRid+'-think');
  var curResp =document.getElementById('asst-'+curRid+'-resp');
  /* Ensure previous round's think is collapsed (safety net). */
  if(curThink&&!curThink.hidden){
    curThink.open=false;
    var s=curThink.querySelector('summary');
    if(s&&s.textContent===('Thinking\u2026'))s.textContent='Thought';
  }
  if(curResp)curResp.innerHTML='';
  var nextR=(msgRounds[id]||1)+1;
  msgRounds[id]=nextR;
  var rounds=document.getElementById('asst-'+id+'-rounds');
  if(!rounds)return;
  var tmp=document.createElement('div');
  tmp.innerHTML=_roundHtml(id,nextR);
  while(tmp.firstChild)rounds.appendChild(tmp.firstChild);
  scrollBottom();
}
function llmSetThink(id,html){
  var rid=_rid(id);
  var think=document.getElementById('asst-'+rid+'-think');
  var body =document.getElementById('asst-'+rid+'-think-body');
  if(!think||!body)return;
  body.innerHTML=html;
  katexEl(body);
  think.hidden=false;
  think.open=true;
  scrollBottom();
}
function llmCollapseThink(id,durationText){
  var rid=_rid(id);
  var think=document.getElementById('asst-'+rid+'-think');
  if(!think)return;
  think.open=false;
  var summary=think.querySelector('summary');
  if(summary)summary.textContent=durationText;
}
function llmSetContent(id,html){
  var resp=document.getElementById('asst-'+_rid(id)+'-resp');
  if(!resp)return;
  resp.innerHTML=html;
  if(typeof hlElement!=='undefined')hlElement(resp);
  katexEl(resp);
  scrollBottom();
}
function llmAddToolCall(id,display,result){
  var tools=document.getElementById('asst-'+_rid(id)+'-tools');
  if(!tools)return;
  var tc=document.createElement('details');
  tc.className='tool-call';
  tc.innerHTML='<summary>'+escHtml(display)+'</summary>'+
               '<div class="tool-result">'+escHtml(result)+'</div>';
  tc.open=true;
  tools.appendChild(tc);
  katexEl(tc);
  scrollBottom();
}
function llmFinalize(id,thinkHtml,contentHtml,rawContent){
  var rid=_rid(id);
  var resp=document.getElementById('asst-'+rid+'-resp');
  var acts=document.getElementById('asst-'+id+'-acts');
  var row =document.getElementById('asst-'+id);
  /* Collapse all think blocks in this message (current + previous rounds). */
  if(row){
    var thinks=row.querySelectorAll('details.think:not([hidden])');
    for(var i=0;i<thinks.length;i++){
      thinks[i].open=false;
      var s=thinks[i].querySelector('summary');
      if(s&&s.textContent===('Thinking\u2026'))s.textContent='Thought';
    }
  }
  if(resp){
    resp.innerHTML=contentHtml;
    if(typeof hlElement!=='undefined')hlElement(resp);
    katexEl(resp);
  }
  if(row&&rawContent)row.dataset.raw=rawContent;
  if(acts){
    var exIdx=parseInt(id.slice(1));
    acts.innerHTML=
      '<button onclick="llmCopyRow(\''+id+'\')">Copy</button>'+
      '<button onclick="llmDeleteExchange('+exIdx+')">Delete</button>';
    acts.hidden=false;
  }
  delete msgRounds[id];
  scrollBottom();
}
function llmSetStats(id,text){
  var el=document.getElementById('asst-'+id+'-stats');
  if(el)el.textContent=text;
}
