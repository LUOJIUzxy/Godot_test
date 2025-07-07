class_name FirebaseConnector
extends HTTPRequest

signal data_stored(success: bool, response: Dictionary)
signal data_retrieved(success: bool, data: Variant)
signal user_profile_updated(success: bool)
signal game_stats_saved(success: bool)

# Firebase Configuration
const FIREBASE_PROJECT_ID = "godottest-2f701"
const FIREBASE_API_KEY = "AIzaSyC_qjxJmv5sX1eDU5i-NPekVSQiu1pDCiQ"
const FIREBASE_AUTH_DOMAIN = "godottest-2f701.firebaseapp.com"
const FIREBASE_DATABASE_URL = "https://godottest-2f701-default-rtdb.europe-west1.firebasedatabase.app"


enum RequestType {
	STORE_USER_WALLET,
	GET_USER_DATA,
	STORE_TRANSACTION,
	STORE_NFT_DATA
}

var current_request_type: RequestType
var user_id: String = ""
var auth_token: String = ""

func _ready():
	request_completed.connect(_on_request_completed)
	# Generate a unique user ID if not exists
	_initialize_user_id()

func _initialize_user_id():
	"""Initialize or retrieve user ID from local storage"""
	
	if user_id == "":
		# generate a simple ID 
		user_id = "user_" + str(Time.get_unix_time_from_system()) + "_" + str(randi())


func store_user_wallet(wallet_data: Dictionary):
	"""Store wallet connection data in Firebase"""
	var data = {
		"wallet_address": wallet_data.get("address", ""),
		"network_id": wallet_data.get("network_id", 0),
		"network_name": wallet_data.get("network_name", ""),
		"last_connected": wallet_data.get("connected_at", 0),
		"updated_at": Time.get_unix_time_from_system()
	}
	
	_make_firebase_request(
		"users/" + user_id + "/wallet.json",
		HTTPClient.METHOD_PUT,
		data,
		RequestType.STORE_USER_WALLET
	)

func get_user_data():
	"""Retrieve user data from Firebase"""
	_make_firebase_request(
		"users/" + user_id + ".json",
		HTTPClient.METHOD_GET,
		{},
		RequestType.GET_USER_DATA
	)


func store_transaction(tx_data: Dictionary):
	"""Store transaction data"""
	var transaction_id = tx_data.get("hash", "unknown_" + str(Time.get_unix_time_from_system()))
	
	var data = {
		"hash": tx_data.get("hash", ""),
		"type": tx_data.get("type", "unknown"), # "purchase", "transfer", "approve", etc.
		"to_address": tx_data.get("to_address", ""),
		"value": tx_data.get("value", "0"),
		"status": tx_data.get("status", "pending"), # "pending", "confirmed", "failed"
		"network_id": tx_data.get("network_id", 0),
		"timestamp": Time.get_unix_time_from_system(),
		"block_number": tx_data.get("block_number", 0),
		"gas_used": tx_data.get("gas_used", 0)
	}
	
	_make_firebase_request(
		"users/" + user_id + "/transactions/" + transaction_id + ".json",
		HTTPClient.METHOD_PUT,
		data,
		RequestType.STORE_TRANSACTION
	)

func store_nft_data(nft_data: Dictionary):
	"""Store NFT ownership data"""
	var token_id = str(nft_data.get("token_id", "unknown"))
	var contract_address = nft_data.get("contract_address", "")
	
	var data = {
		"token_id": token_id,
		"contract_address": contract_address,
		"name": nft_data.get("name", ""),
		"description": nft_data.get("description", ""),
		"image_url": nft_data.get("image_url", ""),
		"attributes": nft_data.get("attributes", []),
		"acquired_at": Time.get_unix_time_from_system(),
		"network_id": nft_data.get("network_id", 0)
	}
	
	var nft_key = contract_address + "_" + token_id
	_make_firebase_request(
		"users/" + user_id + "/nfts/" + nft_key + ".json",
		HTTPClient.METHOD_PUT,
		data,
		RequestType.STORE_NFT_DATA
	)



func authenticate_user(email: String, password: String):
	"""Authenticate user with Firebase Auth (optional)"""
	var auth_url = "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=" + FIREBASE_API_KEY
	
	var auth_data = {
		"email": email,
		"password": password,
		"returnSecureToken": true
	}
	
	var headers = ["Content-Type: application/json"]
	var body = JSON.stringify(auth_data)
	

func _make_firebase_request(endpoint: String, method: HTTPClient.Method, data: Dictionary, request_type: RequestType):
	"""Make a request to Firebase Realtime Database"""
	current_request_type = request_type
	
	var url = FIREBASE_DATABASE_URL + endpoint
	
	# Add auth token if available
	if auth_token != "":
		var separator = "?" if not endpoint.contains("?") else "&"
		url += separator + "auth=" + auth_token
	
	var headers = [
		"Content-Type: application/json",
		"Accept: application/json"
	]
	
	var body = ""
	if method != HTTPClient.METHOD_GET and not data.is_empty():
		body = JSON.stringify(data)
	
	print(" Firebase Request: ", method, " ", endpoint)
	request(url, headers, method, body)

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	"""Handle Firebase response"""
	var success = response_code >= 200 and response_code < 300
	var response_text = body.get_string_from_utf8()
	
	print("Firebase Response: ", response_code, " - ", response_text)
	
	var response_data = {}
	if response_text != "":
		var json = JSON.new()
		var parse_result = json.parse(response_text)
		if parse_result == OK:
			response_data = json.data
	
	# Handle different request types
	match current_request_type:
		RequestType.STORE_USER_WALLET:
			if success:
				print("Wallet data stored successfully")
			else:
				push_error("Failed to store wallet data: " + str(response_code))
			emit_signal("data_stored", success, response_data)
		
		RequestType.GET_USER_DATA:
			if success:
				print("User data retrieved")
				emit_signal("data_retrieved", success, response_data)
			else:
				push_error(" Failed to retrieve user data: " + str(response_code))
				emit_signal("data_retrieved", false, {})
		
		RequestType.STORE_TRANSACTION:
			if success:
				print("Transaction data stored")
			else:
				push_error("Failed to store transaction: " + str(response_code))
			emit_signal("data_stored", success, response_data)
			
		RequestType.STORE_NFT_DATA:
			if success:
				print("NFT data stored")
			else:
				push_error("Failed to store NFT data: " + str(response_code))
			emit_signal("data_stored", success, response_data)


func get_user_id() -> String:
	"""Get current user ID"""
	return user_id

func set_auth_token(token: String):
	"""Set authentication token for Firebase requests"""
	auth_token = token

#func is_connected() -> bool:

	return FIREBASE_PROJECT_ID != "godottest-2f701"  # Basic validation
