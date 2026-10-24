shader_type spatial;
render_mode cull_disabled;
uniform vec3 ship_position = vec3(0.0,0.0,85.0);
uniform vec3 boss_position = vec3(0.0,-11.0,0.0);
uniform float ship_heading = 0.0;
uniform float ship_speed = 0.0;
uniform float clock = 0.0;
varying vec3 ocean_pos;
varying float swell;
varying vec3 ocean_normal;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
float wave(vec2 p){
 float warp=noise(p*.017+vec2(clock*.05,clock*.04))*3.1416;
 vec2 dir=vec2(cos(warp),sin(warp));
 return sin(dot(p,vec2(.075,.125))+clock*.76)*.66+sin(dot(p,vec2(-.16,.065))+clock*1.05)*.34+sin(dot(p,dir)*.11+clock*1.12)*.30+sin(dot(p,vec2(.31,.19))+clock*1.51)*.13;}
void vertex(){
 vec3 p=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 swell=wave(p.xz);
 VERTEX.y+=swell;
 vec2 derivative=vec2(wave(p.xz+vec2(.15,0))-wave(p.xz-vec2(.15,0)),wave(p.xz+vec2(0,.15))-wave(p.xz-vec2(0,.15)))/.3;
 ocean_normal=normalize(vec3(-derivative.x,1.0,-derivative.y));
 NORMAL=ocean_normal;
 ocean_pos=p+vec3(0,swell,0);
}
void fragment(){
 vec2 p=ocean_pos.xz;
 float n=noise(p*.47+vec2(clock*.24,-clock*.33));
 float fine=noise(p*3.7+vec2(clock*.55,-clock*.38));
 float cap=smoothstep(.65,1.05,swell)*smoothstep(.54,.83,n)*smoothstep(.25,.7,fine)*.24;
 float boss_dist=length(p-boss_position.xz);
 float churn=exp(-abs(boss_dist-25.0)*.28)*smoothstep(.44,.76,n)*.27;
 vec2 boat=p-ship_position.xz;
 // Inverse Y rotation: local +Z is stern, local -Z points forward.
 boat=vec2(cos(ship_heading)*boat.x-sin(ship_heading)*boat.y,sin(ship_heading)*boat.x+cos(ship_heading)*boat.y);
 float speed=clamp(abs(ship_speed)/18.0,0.0,1.0);
 float width=2.7+max(0.0,boat.y+5.0)*.22;
 float trail=exp(-abs(abs(boat.x)-width)*2.3)*smoothstep(-7.5,0.0,boat.y)*(1.0-smoothstep(14.0,40.0,boat.y));
 float keel=exp(-boat.x*boat.x*.18)*smoothstep(2.0,8.0,boat.y)*(1.0-smoothstep(12.0,36.0,boat.y));
 float wake=(trail*.43+keel*.12)*smoothstep(.24,.72,n)*speed;
 float foam=clamp(cap+churn+wake,0.0,.55);
 vec3 base=mix(vec3(.006,.017,.029),vec3(.018,.051,.073),clamp(swell*.24+.42,0.0,1.0));
 vec3 view_dir=normalize(CAMERA_POSITION_WORLD-ocean_pos);
 float grazing=pow(1.0-clamp(view_dir.y,0.0,1.0),3.0);
 ALBEDO=mix(base,vec3(.52,.62,.66),foam);
 ALBEDO+=vec3(.020,.048,.068)*grazing;
 METALLIC=0.0;
 // Break the broad silver patch into a glancing wet reflection.
 ROUGHNESS=mix(.36+fine*.10,.82,foam);
 SPECULAR=.34;
 // The horizon does not author UV/tangents. Perturb the world-space
 // surface normal directly, so near grid and far mesh share identical shading.
 // Fade unresolved capillary ripples with distance to avoid sparkling pixels.
 vec2 drift=vec2(clock*.42,-clock*.28);
 float ripple_a=(noise(p*1.7+drift+vec2(.12,0))-noise(p*1.7+drift-vec2(.12,0)))*2.6;
 float ripple_b=(noise(p*1.7+drift+vec2(0,.12))-noise(p*1.7+drift-vec2(0,.12)))*2.6;
 float visible_ripple=1.0-smoothstep(35.0,170.0,length(p-CAMERA_POSITION_WORLD.xz));
 float crossing=cos(dot(p,vec2(3.8,-2.1))+clock*2.3)*.035;
 vec3 micro_normal=normalize(ocean_normal+vec3(-(ripple_a*.17+crossing)*visible_ripple,0.0,-(ripple_b*.14-crossing)*visible_ripple));
 NORMAL=normalize((VIEW_MATRIX*vec4(micro_normal,0.0)).xyz);
 EMISSION=vec3(.03,.26,.32)*churn*2.4;
}
