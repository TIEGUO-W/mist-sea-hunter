shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
void fragment() {
 vec3 c=texture(screen_tex,SCREEN_UV).rgb;
 vec2 p=UV-.5;
 float vignette=1.0-smoothstep(.25,.75,length(p))*.32;
 float grain=(fract(sin(dot(FRAGCOORD.xy+TIME,vec2(12.9898,78.233)))*43758.5453)-.5)*.012;
 COLOR=vec4(c*vignette+grain,1.0);
}
