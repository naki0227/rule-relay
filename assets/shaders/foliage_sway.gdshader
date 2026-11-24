// 草花・木の葉のそよぎ（src/game/foliage.gd）。根もと（y = 0）は動かさず、高さの2乗で先だけを揺らす。
// となりどうしで揺れがそろわないよう、置いた場所で位相をずらす。strength = 0 なら揺れない（画質の低）。
shader_type spatial;

uniform vec4 albedo : source_color = vec4(1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.85;
// モデルの高さ（m）。
uniform float height = 0.3;
// 揺れの大きさ（高さに対する割合）。
uniform float amount = 0.15;
uniform float strength = 1.0;
uniform float speed = 1.3;

void vertex() {
	if (strength > 0.0) {
		vec3 origin = MODEL_MATRIX[3].xyz;
		float k = clamp(VERTEX.y / height, 0.0, 1.0);
		k *= k;
		float t = TIME * speed + origin.x * 0.37 + origin.z * 0.23;
		float sway = sin(t) * 0.65 + sin(t * 2.3 + 1.7) * 0.2;
		float reach = strength * amount * height * k;
		VERTEX.x += sway * reach;
		VERTEX.z += cos(t * 0.8 + 0.6) * 0.5 * reach;
	}
}

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = roughness;
}
