// メニューの背景: 後ろのゲーム画面をぼかして暗くする（AAA のポーズ画面の定番）。
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float blur_lod : hint_range(0.0, 6.0) = 3.0;
uniform vec4 tint : source_color = vec4(0.03, 0.035, 0.05, 0.58);
uniform float vignette : hint_range(0.0, 1.0) = 0.35;

void fragment() {
	vec3 blurred = textureLod(screen_texture, SCREEN_UV, blur_lod).rgb;
	vec3 tinted = mix(blurred, tint.rgb, tint.a);
	float d = distance(SCREEN_UV, vec2(0.5));
	tinted *= 1.0 - vignette * smoothstep(0.35, 0.85, d);
	COLOR = vec4(tinted, 1.0);
}
