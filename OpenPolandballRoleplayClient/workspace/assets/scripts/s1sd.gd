extends Node

var likelychatting = false
var username = "tester"
var password = "654321"
var country = "TUR_Republic"
var ip_address = "localhost"
var port = 8765
var commandtosend = null
var mapload = ""

# Called when the node enters the scene tree for the first time.
func _ready():
	pass

func set_player_name(name):
	username = name

func set_password(psw):
	password = psw

func set_country(cntry):
	country = cntry

func set_ip_address(ip):
	ip_address = ip

func set_map(map):
	mapload = map

func set_port(prt):
	port = prt
