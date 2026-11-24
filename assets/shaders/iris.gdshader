// ステージの出入りの「丸く開く」幕（src/ui/stage_transition.gd）。progress 0 で全面が生成り、1 で全部見える。
// 縁はやわらかくぼかす（くっきりした輪だと、はさみで切ったように見えるので）。
shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(1.0, 0.973, 0.925, 1.0);
uniform float softness = 0.12;

void fragment() {
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 p = (UV - vec2(0.5)) * vec2(aspect, 1.0);
	// 画面の隅まで届く半径（対角線の半分）より少し大きく開く
	float reach = length(vec2(aspect, 1.0)) * 0.5 + softness;
	float radius = progress * reach;
	float cover = smoothstep(radius - softness, radius, length(p));
	COLOR = vec4(tint.rgb, tint.a * cover);
}
