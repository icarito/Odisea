// Self-check for the HTML5 shell's "tiempo restante" line (odisea_shell.html).
// Mirrors the damping + sticky-render logic. Fails if the number churns.
var etaShownSec = 0, etaShownTs = 0, etaRendered = 0, out = [];
function fmtEta(s){ if(!isFinite(s)||s<=0) return ""; s = s>=60 ? Math.ceil(s/10)*10 : Math.ceil(s);
  if(s<60) return "~"+s+" s"; var m=Math.floor(s/60), r=s%60; return "~"+m+" min"+(r?" "+r+" s":""); }
function tick(now, eta){
  if(!(eta>0 && now-etaShownTs>=1000)) return;
  var decayed = etaShownSec>0 ? etaShownSec-(now-etaShownTs)/1000 : eta;
  etaShownSec = Math.max(1, decayed*0.8 + eta*0.2); etaShownTs = now;
  var step = etaShownSec>=60 ? 10 : 1;
  if(etaRendered===0 || etaShownSec<=etaRendered-step || etaShownSec>=etaRendered+2*step){
    etaRendered = etaShownSec; out.push(fmtEta(etaRendered));
  }
}
var secs = function(v){ var m=v.match(/(\d+) min/), s=v.match(/(\d+) s/);
  return (m?+m[1]*60:0)+(s?+s[1]:0); };

// 40 s of bursty chunks every 100 ms; true ETA trends 90 -> 50 s with +-15% noise.
for (var i=0;i<400;i++) tick(i*100, (90-i*0.1)*(1+Math.sin(i*1.7)*0.15));
console.assert(out.length<=41, "throttle failed: "+out.length+" repaints in 40 s");
var rises = out.filter(function(v,i){ return i && secs(v) > secs(out[i-1]); });
console.assert(rises.length===0, "countdown jitters: "+rises.length+" rises in "+out.join(","));
console.assert(secs(out[out.length-1]) < secs(out[0]), "never counted down");

// A sustained worse estimate must still be reflected, not pinned optimistically.
etaShownSec=30; etaShownTs=0; etaRendered=30;
for(var t=1;t<=40;t++) tick(t*1000, 120);
console.assert(etaRendered>100, "never recovered upward: "+etaRendered);
console.log("ok - repaints:", out.length, "rises:", rises.length,
            "| first/last:", out[0], out[out.length-1]);
