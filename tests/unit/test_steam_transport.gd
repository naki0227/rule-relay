extends TestCase
## Steam の差し替え口は、GodotSteam が無い環境（提出版・CI）では何もせずに「使えない」と答える。


func test_not_available_without_godotsteam() -> void:
	assert_false(SteamTransport.is_available())
	assert_false(SteamTransport.start())
	assert_eq(SteamTransport.make_host_peer(), null)
	assert_eq(SteamTransport.make_client_peer(1234), null)
