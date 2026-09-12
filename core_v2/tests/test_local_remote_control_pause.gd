extends GdUnitTestSuite

# test_local_remote_control_pause.gd - Con el control remoto corriendo en la misma maquina
# no se pausa al perder el foco (alt-tab entre las dos ventanas es parte de jugar).

const RemoteControlServerScript = preload("res://core_v2/net/RemoteControlServer.gd")

class DummyServer extends Node:
	var local: bool = false
	func has_local_paired_client() -> bool:
		return local

func test_loopback_and_own_addresses_are_local():
	var server = auto_free(RemoteControlServerScript.new())

	assert_bool(server.is_local_address("127.0.0.1")).is_true()
	assert_bool(server.is_local_address("::1")).is_true()
	# Un cliente IPv4 sobre socket IPv6 llega asi.
	assert_bool(server.is_local_address("::ffff:127.0.0.1")).is_true()
	# Y la misma maquina por su IP de LAN (es la que se anuncia por UDP).
	var own: Array = IP.get_local_addresses()
	if not own.empty():
		assert_bool(server.is_local_address(String(own[0]))).is_true()

func test_other_devices_are_not_local():
	var server = auto_free(RemoteControlServerScript.new())

	assert_bool(server.is_local_address("192.168.18.11")).is_false() # el celu
	assert_bool(server.is_local_address("")).is_false()

func test_server_reports_no_local_client_while_stopped():
	var server = auto_free(RemoteControlServerScript.new())
	# Sin servidor levantado no hay a quien preguntarle (ni _peers ni WebSocketServer).
	assert_bool(server.has_local_paired_client()).is_false()

func test_manager_requires_active_host_and_local_client():
	var mgr = auto_free(load("res://core_v2/net/RemoteControlManager.gd").new())
	var server = auto_free(DummyServer.new())
	mgr.server = server

	mgr.is_host_active = false
	server.local = true
	assert_bool(mgr.has_local_remote_control()).is_false() # no esta hosteando

	mgr.is_host_active = true
	server.local = false
	assert_bool(mgr.has_local_remote_control()).is_false() # el control esta en otro equipo

	server.local = true
	assert_bool(mgr.has_local_remote_control()).is_true()

func test_pause_and_audio_consult_the_same_manager():
	# El guard de los dos sale de ahi: si el manager dice que si, no se pausa ni se mutea.
	assert_bool(PauseManager.has_method("_controlled_from_this_machine")).is_true()
	assert_bool(PauseManager._controlled_from_this_machine()).is_false()
	assert_bool(AudioManager.has_method("_controlled_from_this_machine")).is_true()
	assert_bool(AudioManager._controlled_from_this_machine()).is_false()
