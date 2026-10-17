extends Node
## A stand-in language model for tests/net_test.gd: answers every OpenAI-style chat
## request on 127.0.0.1 with the same line, so the test can check that a player without
## a model of their own talks through the server's.

const LINE := "hello from the server"

var hits := 0
var _server := TCPServer.new()
var _conns: Array = [] ## [StreamPeerTCP, bytes so far]

func start(port: int) -> bool:
	return _server.listen(port, "127.0.0.1") == OK

func _process(_delta: float) -> void:
	while _server.is_connection_available():
		_conns.append([_server.take_connection(), PackedByteArray()])
	for c in _conns.duplicate():
		var s: StreamPeerTCP = c[0]
		s.poll()
		if s.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_conns.erase(c)
			continue
		var n := s.get_available_bytes()
		if n > 0:
			var got: PackedByteArray = c[1]
			got.append_array(s.get_data(n)[1])
			c[1] = got # packed arrays are copied, not shared
		var text: String = (c[1] as PackedByteArray).get_string_from_utf8()
		var head := text.find("\r\n\r\n")
		if head < 0:
			continue
		var length := 0
		for line in text.substr(0, head).split("\r\n"):
			if line.to_lower().begins_with("content-length:"):
				length = line.substr(15).strip_edges().to_int()
		if (c[1] as PackedByteArray).size() < head + 4 + length:
			continue
		hits += 1
		var body := JSON.stringify({"choices": [{"message": {"role": "assistant", "content": JSON.stringify({"say": LINE})}}]})
		var reply := "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" % [body.to_utf8_buffer().size(), body]
		s.put_data(reply.to_utf8_buffer())
		s.disconnect_from_host()
		_conns.erase(c)

func _exit_tree() -> void:
	_server.stop()
