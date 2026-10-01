export const palettes = {
  light: {accent:'#1d7abd', text:'#202b38', muted:'#506174', dim:'#506174', border:'#507a9c', background:'#ffffff', panel:'#edf4fb', selected:'#dcebf9', success:'#237345', warning:'#875b00', error:'#b52d3c', secondary:'#644da8'},
  dark: {accent:'#72baff', text:'#e5edf7', muted:'#a6b7ca', dim:'#a6b7ca', border:'#668aaf', background:'#101820', panel:'#192a3b', selected:'#263f59', success:'#81c99c', warning:'#ecc477', error:'#ff9ca6', secondary:'#b6a5f5'},
};
export function resolveAppearance(preference, themeName='', colorfgbg='') {
  if (preference==='light'||preference==='dark') return preference;
  const last=colorfgbg.split(';').at(-1);
  if(last && /^\d+$/.test(last)) {
    const bg=Number(last);
    if(bg===7||bg===15)return 'light';
    if(bg===0||bg===8)return 'dark';
  }
  return /light/i.test(themeName) ? 'light' : 'dark';
}
export function contrast(a,b){
 const lum=h=>{const rgb=[1,3,5].map(i=>parseInt(h.slice(i,i+2),16)/255).map(n=>n<=0.04045?n/12.92:((n+0.055)/1.055)**2.4);return rgb[0]*.2126+rgb[1]*.7152+rgb[2]*.0722;};
 const x=lum(a),y=lum(b);return (Math.max(x,y)+.05)/(Math.min(x,y)+.05);
}
