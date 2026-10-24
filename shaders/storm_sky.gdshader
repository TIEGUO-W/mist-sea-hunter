shader_type sky;
render_mode use_quarter_res_pass;
float hash(vec3 p) { return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453); }
float noise(vec3 p) {
 vec3 i=floor(p),f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(mix(hash(i),hash(i+vec3(1,0,0)),f.x),mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y),f.z);
}
float fbm(vec3 p) {
 float v=0.0,a=.5;
 for(int i=0;i<5;i++) { v+=a*noise(p); p=p*2.03+vec3(13.2,2.1,7.7); a*=.5; }
 return v;
}
void sky() {
 vec3 d=normalize(EYEDIR);
 float horizon=pow(1.0-max(d.y,0.0),5.0);
 vec3 color=mix(vec3(.009,.017,.032),vec3(.09,.145,.178),horizon);
 vec3 cloudp=vec3(d.x*3.5,d.y*7.0,d.z*3.5)+vec3(TIME*.004,0.0,TIME*.002);
 float clouds=fbm(cloudp);
 float layers=smoothstep(.35,.67,clouds);
 vec3 moon_dir=normalize(vec3(-.42,.31,-1.0));
 float moon=dot(d,moon_dir);
 float moon_disk=smoothstep(.99945,.99965,moon);
 float corona=pow(max(moon,0.0),95.0)*.20;
 color+=vec3(.26,.36,.43)*corona;
 color=mix(color,mix(vec3(.017,.026,.04),vec3(.10,.135,.16),clouds),layers*.85);
 color+=vec3(.50,.61,.65)*moon_disk*(1.0-layers*.78);
 float silver=pow(max(moon,0.0),22.0)*pow(max(0.0,1.0-abs(clouds-.52)*3.0),5.0)*.11;
 color+=vec3(.28,.38,.45)*silver;
 COLOR=color;
}
